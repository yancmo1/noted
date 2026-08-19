// JSON storage is single-writer. Processing now runs inside server.ts; keeping
// this entry point as a failing shim prevents an accidental second writer.
console.error("The standalone worker is retired. Start the API server instead.");
process.exitCode = 1;
