import { store } from "./db.js";
import { processSource } from "./processor.js";
async function tick(){for(const job of store.pendingJobs()){if(job.attempts<3)await processSource(job.sourceId,job.id);}}
await tick();
setInterval(tick,5000);
