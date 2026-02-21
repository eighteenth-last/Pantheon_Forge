/**
 * 终端工具 - 命令执行描述
 */
export const terminalToolSchema = {
  run_terminal: {
    name: 'run_terminal',
    description: '在终端执行命令',
    parameters: {
      type: 'object' as const,
      properties: {
        command: { type: 'string', description: '要执行的终端命令' }
      },
      required: ['command']
    }
  }
}

/** 危险命令黑名单 */
export const DANGEROUS_PATTERNS = [
  'rm -rf /',
  'format c:',
  'shutdown',
  'del /f /s /q c:',
  'rmdir /s /q c:',
  ':(){:|:&};:',
  'mkfs',
  'dd if='
]

export function isDangerous(command: string): boolean {
  const lower = command.toLowerCase()
  return DANGEROUS_PATTERNS.some(p => lower.includes(p))
}
