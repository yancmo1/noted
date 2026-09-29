export interface ProcessingLogger {
  info(fields: Record<string, unknown>, message?: string): void;
  error(fields: Record<string, unknown>, message?: string): void;
}

const fallbackLogger: ProcessingLogger = {
  info(fields, message) {
    process.stderr.write(`${JSON.stringify({ level: "info", message, ...fields })}\n`);
  },
  error(fields, message) {
    process.stderr.write(`${JSON.stringify({ level: "error", message, ...fields })}\n`);
  },
};

let logger: ProcessingLogger = fallbackLogger;

export function setProcessingLogger(next: ProcessingLogger) {
  logger = next;
}

export function processingInfo(fields: Record<string, unknown>, message?: string) {
  logger.info({ component: "noted-processing", ...fields }, message);
}

export function processingError(fields: Record<string, unknown>, message?: string) {
  logger.error({ component: "noted-processing", ...fields }, message);
}
