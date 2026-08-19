import { buildApp } from "./app.js";
import { startJobScheduler } from "./jobs.js";
import { config } from "./config.js";

const app = await buildApp();
const stopScheduler = startJobScheduler();

const shutdown = async () => {
  stopScheduler();
  await app.close();
  process.exit(0);
};

process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);

await app.listen({ port: config.port, host: "0.0.0.0" });
app.log.info(`Memory Garden API listening on ${config.port}`);
