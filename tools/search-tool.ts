/**
 * 搜索工具 - 项目内文件搜索
 */
export const searchToolSchema = {
  search_files: {
    name: 'search_files',
    description: '在项目中搜索包含指定文本的文件',
    parameters: {
      type: 'object' as const,
      properties: {
        query: { type: 'string', description: '搜索关键词' },
        pattern: { type: 'string', description: '文件名匹配模式，如 *.ts' }
      },
      required: ['query']
    }
  }
}
