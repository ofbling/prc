# prc — dbt on Databricks with CI/CD

A dbt project that turns the Databricks `samples.tpch` dataset into a small star schema. GitHub Actions builds it into a **dev** or **prod** schema, depending on the branch.

```
samples.tpch (raw)  ──►  staging views  ──►  marts tables (dims + fact)
                             prc.<target schema>
```

---

## Repository layout

```
.
├── .github/workflows/dbt.yml     # CI/CD pipeline (dev + prod)
└── prc/                          # dbt project root
    ├── dbt_project.yml           # project config & materializations
    ├── profiles.yml              # Databricks connection (dev / prod targets)
    ├── models/
    │   ├── staging/
    │   │   ├── sources.yml       # tpch source declaration
    │   │   ├── stg_tpch__customers.sql
    │   │   ├── stg_tpch__orders.sql
    │   │   ├── stg_tpch__lineitem.sql
    │   │   └── stg_tpch__part.sql
    │   └── marts/
    │       ├── _marts.yml        # tests for mart models
    │       ├── dim_customer.sql
    │       ├── dim_parts.sql
    │       └── fact_orders.sql
    ├── analyses/  macros/  seeds/  snapshots/  tests/   # (empty placeholders)
```

---

## Data model

### Source

| Source | Location | Tables |
|---|---|---|
| `tpch` | `samples.tpch` (Databricks built-in sample catalog) | `customer`, `orders`, `lineitem`, `part` |

### Staging layer (`models/staging`, materialized as **views**)

Each staging model is a 1:1 view over a source table. It renames the cryptic TPC-H columns (`c_custkey`, `o_orderdate`, …) to readable names and keeps only the columns needed downstream.

| Model | Source table | Key columns |
|---|---|---|
| `stg_tpch__customers` | `customer` | `customer_key`, `customer_name`, `customer_address`, `phone` |
| `stg_tpch__orders` | `orders` | `order_key`, `customer_key`, `order_status`, `total_price`, `order_date`, … |
| `stg_tpch__lineitem` | `lineitem` | `order_key`, `part_key`, `supplier_address`, `quantity` |
| `stg_tpch__part` | `part` | `part_key`, `part_name`, `brand`, `retail_price` |

### Marts layer (`models/marts`, materialized as **tables**)

A star schema with one fact table and two dimensions:

```
        dim_customer                 dim_parts
      (customer_key) ◄──┐       ┌──► (part_key)
                        │       │
                     fact_orders
        (one row per order line item)
```

| Model | Grain | Built from |
|---|---|---|
| `dim_customer` | one row per customer | `stg_tpch__customers` |
| `dim_parts` | one row per part | `stg_tpch__part` |
| `fact_orders` | one row per order line item | `stg_tpch__lineitem` inner join `stg_tpch__orders` on `order_key` |

### Tests

Defined in [prc/models/marts/_marts.yml](prc/models/marts/_marts.yml):

- `fact_orders.customer_key` → `relationships` test against `dim_customer.customer_key`
- `fact_orders.part_key` → `relationships` test against `dim_parts.part_key`

`dbt build` runs these tests after it builds the models.

---

## Environments

Both targets are defined in [prc/profiles.yml](prc/profiles.yml). They use the same Databricks workspace and catalog and write to different schemas:

| Target | Catalog | Schema | Used by |
|---|---|---|---|
| `dev` (default) | `prc` | `dev` | local development, pushes to `dev`, PRs into `main` |
| `prod` | `prc` | `prod` | pushes / merges to `main` |

The connection details come from environment variables:

| Variable | Description |
|---|---|
| `DBT_HOST` | Databricks workspace hostname, e.g. `adb-1234567890.12.azuredatabricks.net` (no `https://`) |
| `DBT_HTTP_PATH` | HTTP path of the SQL warehouse or cluster, e.g. `/sql/1.0/warehouses/abc123` |
| `DBT_TOKEN` | Databricks personal access token (or service principal token) |

> The `prc` catalog must exist in Unity Catalog. The token's principal needs permission to create schemas and tables in it, and to read from `samples.tpch`.

---

## CI/CD

The pipeline is defined in [.github/workflows/dbt.yml](.github/workflows/dbt.yml).

| Trigger | Target | Command |
|---|---|---|
| Push to `dev` | `dev` | `dbt build --target dev` |
| Pull request into `main` | `dev` | `dbt build --target dev` |
| Push to `main` (e.g. merged PR) | `prod` | `dbt build --target prod` |

Each run:
1. Checks out the repo.
2. Sets up Python 3.12 and installs `dbt-databricks`.
3. Runs `dbt build` from the `prc/` directory with `--profiles-dir .`, which builds the models and runs the tests in DAG order.

### Required GitHub secrets

Add these under **Settings → Secrets and variables → Actions**:

- `DBT_HOST`
- `DBT_HTTP_PATH`
- `DBT_TOKEN`

### Branching workflow

```
feature work ──► dev ──(PR)──► main
                 │               │
            builds dev      PR: validated against dev
                            merge: deployed to prod
```

1. Commit and push to `dev`. CI builds and tests the models in the `dev` schema.
2. Open a PR from `dev` into `main`. CI validates the PR against `dev`.
3. Merge the PR. CI builds and tests the models in the `prod` schema.

---

## Local development

### Prerequisites

- Python 3.9+ (CI uses 3.12)
- A Databricks workspace with Unity Catalog, a SQL warehouse or cluster, and a token
- dbt-core 1.10+ (the tests use the `data_tests` / `arguments:` syntax)

### Setup

```bash
# 1. Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate

# 2. Install the Databricks adapter (pulls in dbt-core)
pip install dbt-databricks

# 3. Export connection details
export DBT_HOST="<workspace-host>"
export DBT_HTTP_PATH="<http-path>"
export DBT_TOKEN="<token>"
# PowerShell: $env:DBT_HOST="<workspace-host>"  (etc.)

# 4. Move into the dbt project
cd prc
```

### Common commands

Run all of these from `prc/`, the folder that contains `profiles.yml`:

```bash
dbt debug  --profiles-dir .                 # verify the connection
dbt build  --profiles-dir .                 # build + test everything in dev
dbt build  --profiles-dir . --target prod   # build + test in prod (use with care)
dbt run    --profiles-dir . -s marts        # run only the marts models
dbt test   --profiles-dir . -s fact_orders  # test one model
dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .
```

---

## Adding a new model

1. **New source table:** add it to [prc/models/staging/sources.yml](prc/models/staging/sources.yml).
2. **Staging:** create `stg_tpch__<table>.sql` in `models/staging/`. It should only rename and select columns, with no business logic.
3. **Marts:** build the dimensions and facts in `models/marts/` with `ref()` to staging models.
4. **Tests:** declare tests in `_marts.yml` (or a `_staging.yml` for staging models).
5. Push to `dev` and let CI validate the change before you open a PR into `main`.
