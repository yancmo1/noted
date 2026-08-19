import { store } from "./db.js";
import { queueSource } from "./processor.js";
const examples=[
  ["Project Atlas decision","I decided that Project Atlas will use SQLite because it is easy to deploy."],
  ["Project Atlas updated decision","I changed my mind about Atlas. We are using PostgreSQL instead of SQLite."],
  ["Atlas follow-up","I still need to migrate the old Atlas records this weekend."],
  ["MineOps idea","An idea for MineOps: make the fragments bar easier to discover."],
  ["Training note","I should ask Bill about the training cohort next week."]
];
for(const [title,text] of examples){const s=store.createSource({type:"note",title,originalText:text,extractedText:text});queueSource(s.id);}
console.log(`Seeded ${examples.length} memories.`);
