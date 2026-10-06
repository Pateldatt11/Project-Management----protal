type LogData = Record<string, unknown>;

function write(level: "INFO" | "WARN" | "ERROR", message: string, data?: LogData): void {
  const output = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...(data ?? {}),
  };
  const text = JSON.stringify(output);
  if (level === "ERROR") console.error(text);
  else if (level === "WARN") console.warn(text);
  else console.log(text);
}

export const log = {
  info: (message: string, data?: LogData) => write("INFO", message, data),
  warn: (message: string, data?: LogData) => write("WARN", message, data),
  error: (message: string, data?: LogData) => write("ERROR", message, data),
};
