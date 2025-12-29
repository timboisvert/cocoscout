## Plan: Migrate Production DB to RDS PostgreSQL & Repurpose Supabase for Dev

Migrate your production PostgreSQL from Supabase to AWS RDS PostgreSQL with zero downtime, using a single database for app, cache, and queue. Then reconfigure development to use the old Supabase instance.

### Steps

1. **Provision AWS RDS PostgreSQL instance** - Create an RDS PostgreSQL instance in us-east-2 (same region as your EC2). Use db.t4g.micro or db.t4g.small to start (~$15-30/mo). Enable Multi-AZ for reliability if desired. Create one database: `cocoscout_production`.

2. **Set up RDS credentials in 1Password** - Add `DATABASE_URL_RDS` secret to your CocoScoutProductionPasswords vault. Keep the existing `DATABASE_URL` (Supabase) intact during migration.

3. **Update database.yml for single PostgreSQL database** - Modify database.yml production section to use PostgreSQL with cache and queue pointing to the same database.

4. **Enable logical replication on Supabase** - In Supabase dashboard, enable `wal_level=logical`. This allows real-time replication to RDS during the cutover window.

5. **Use AWS DMS for migration** - Create an AWS Database Migration Service task to continuously replicate from Supabase to RDS. Use "full load + CDC" mode for zero-downtime migration.

6. **Update deploy.yml and secrets for cutover** - Update `DATABASE_URL` in 1Password to point to RDS, then run `kamal deploy`. Run `rails db:prepare` to create cache/queue tables.

7. **Reconfigure development for Supabase** - Update database.yml development section to use PostgreSQL with `SUPABASE_DEV_DATABASE_URL`.

---

### Updated database.yml

```yaml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

postgres_default: &postgres_default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("DB_POOL") { ENV.fetch("RAILS_MAX_THREADS") { 5 } } %>
  prepared_statements: false

development:
  primary:
    <<: *postgres_default
    url: <%= ENV["SUPABASE_DEV_DATABASE_URL"] %>
  cache:
    <<: *postgres_default
    url: <%= ENV["SUPABASE_DEV_DATABASE_URL"] %>
    migrations_paths: db/cache_migrate
  queue:
    <<: *postgres_default
    url: <%= ENV["SUPABASE_DEV_DATABASE_URL"] %>
    migrations_paths: db/queue_migrate

test:
  <<: *default
  database: storage/test.sqlite3

production:
  primary:
    <<: *postgres_default
    url: <%= ENV["DATABASE_URL"] %>
  cache:
    <<: *postgres_default
    url: <%= ENV["DATABASE_URL"] %>
    migrations_paths: db/cache_migrate
  queue:
    <<: *postgres_default
    url: <%= ENV["DATABASE_URL"] %>
    migrations_paths: db/queue_migrate
```

---

### Updated deploy.yml (env section)

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - AWS_ACCESS_KEY_ID
    - AWS_SECRET_ACCESS_KEY
    - MAILGUN_API_KEY
    - SENTRY_DSN
  clear:
    SOLID_QUEUE_IN_PUMA: true
    JOB_CONCURRENCY: 3
    WEB_CONCURRENCY: 1
    RAILS_MAX_THREADS: 5
    DB_POOL: 5
    RAILS_ENV: production
```

**Removed:** `CACHE_DATABASE_URL` and `QUEUE_DATABASE_URL` since everything uses `DATABASE_URL`.

---

### Secrets in 1Password

| Secret Name | Value Format |
|-------------|--------------|
| `DATABASE_URL` | `postgres://user:password@your-rds-instance.us-east-2.rds.amazonaws.com:5432/cocoscout_production` |

---

### Local development setup

Create or update your `.env` or use direnv with `.envrc`:

```bash
export SUPABASE_DEV_DATABASE_URL="postgres://postgres.[project-ref]:[password]@aws-0-us-east-2.pooler.supabase.com:6543/postgres"
```

---

### Migration steps (in order)

1. **Run cache/queue migrations on RDS** (after DMS sync completes):
   ```bash
   kamal app exec "bin/rails db:migrate:cache"
   kamal app exec "bin/rails db:migrate:queue"
   ```

2. **Drain the queue** before switching:
   ```bash
   kamal app exec "bin/rails runner 'sleep 30 while SolidQueue::Job.where(finished_at: nil).exists?'"
   ```

3. **Deploy with new config** - Update `DATABASE_URL` in 1Password to RDS, then:
   ```bash
   kamal deploy
   ```

---

### Further Considerations

1. **RDS instance sizing** — Start with db.t4g.small (~$25/mo). You can resize later without downtime using "Apply immediately" option.

2. **Connection pooling** — RDS doesn't include built-in pooling like Aurora. Consider adding PgBouncer if you scale to multiple app instances, or use RDS Proxy (~$20/mo additional).

3. **Rollback strategy** — Keep Supabase active for 48-72 hours post-migration. If issues arise, revert `DATABASE_URL` to Supabase in 1Password and redeploy.
