import knex, { Knex } from "knex";

function createDb(): Knex {
  return knex({
    client: "pg",
    connection: {
      host: process.env.PGHOST ?? "localhost",
      port: Number(process.env.PGPORT ?? 5432),
      database: process.env.PGDATABASE ?? "customer_analytics",
      user: process.env.PGUSER ?? "app",
      password: process.env.PGPASSWORD ?? "app_password"
    },
    pool: {
      min: 0,
      max: Number(process.env.PGPOOL_MAX ?? 10)
    }
  });
}

export { createDb };
