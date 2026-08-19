import { config } from "./config.js";
import { store } from "./db.js";
import { processSource } from "./processor.js";

let timer: NodeJS.Timeout | undefined;
let ticking = false;

export async function tickJobs() {
  if (ticking) return;
  ticking = true;
  try {
    store.recoverStaleJobs(config.jobLeaseMs);
    for (const job of store.pendingJobs()) {
      if (job.attempts >= config.jobMaxAttempts) {
        store.updateJob(job.id, "failed", job.error ?? "The processing retry limit was reached.");
        continue;
      }
      await processSource(job.sourceId, job.id);
    }
  } finally {
    ticking = false;
  }
}

export function startJobScheduler() {
  void tickJobs();
  timer = setInterval(() => { void tickJobs(); }, config.jobPollMs);
  return () => {
    if (timer) clearInterval(timer);
    timer = undefined;
  };
}
