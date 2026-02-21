/**
 * 文件工具 - 封装文件操作供 Agent 使用
 * 实际执行逻辑在 tool-executor.ts 中
 * 这里提供工具描述和参数校验
 */
export const fileToolSchema = {
  read_file: {
    name: 'read_file',
    description: '读取项目中的文件内容',
    parameters: {
      type: 'object' as const,
      properties: {
        path: { type: 'string', description: '相对于项目根目录的文件路径' }
      },
      required: ['path']
    }
  },
  write_file: {
    name: 'write_file',
    description: '写入或创建文件',
    parameters: {
      type: 'object' as const,
      properties: {
        path: { type: 'string', description: '相对于项目根目录的文件路径' },
        content: { type: 'string', description: '文件内容' }
      },
      required: ['path', 'content']
    }
  },
  list_dir: {
    name: 'list_dir',
    description: '列出目录下的文件和子目录',
    parameters: {
      type: 'object' as const,
      properties: {
        path: { type: 'string', description: '相对于项目根目录的目录路径' }
      }
    }
  }
}
