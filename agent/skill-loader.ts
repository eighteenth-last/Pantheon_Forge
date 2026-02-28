/**
 * SkillLoader — 从本地 skills/ 目录加载内置 Skill 内容
 *
 * Skills 内置在项目 skills/ 文件夹中，按 slug 组织：
 *   skills/{category}/{name}/SKILL.md
 *
 * index.json 作为注册表，记录所有可用 Skill 的元信息。
 * SkillLoader 根据 SkillItem 配置读取对应的 SKILL.md 内容注入到 system prompt。
 */
import { readdir, readFile, access } from 'fs/promises'
import { join } from 'path'

export interface SkillContent {
  name: string
  content: string
  slug: string
  loadedAt: number
}

export interface SkillItem {
  name: string
  slug: string        // 如 "community/code-review"
  enabled: boolean
}

export interface SkillRegistryEntry {
  slug: string
  name: string
  summary: string
  tags: string[]
  version: string
  status: string
}

export class SkillLoader {
  private skillsDir: string

  constructor(skillsDir: string) {
    this.skillsDir = skillsDir
  }

  /** 批量加载所有已启用的 Skills，跳过失败的 */
  async loadAllSkills(skills: SkillItem[]): Promise<SkillContent[]> {
    const enabled = skills.filter(s => s.enabled)
    const results: SkillContent[] = []
    for (const skill of enabled) {
      try {
        const content = await this.loadSkill(skill)
        if (content) results.push(content)
      } catch (err) {
        console.error(`[SkillLoader] 加载 Skill "${skill.name}" 失败:`, err)
      }
    }
    return results
  }

  /** 加载单个 Skill：从本地 skills/ 目录读取 SKILL.md */
  async loadSkill(skill: SkillItem): Promise<SkillContent | null> {
    try {
      const content = await this.readSkillContent(skill.slug)
      if (!content) {
        console.warn(`[SkillLoader] Skill "${skill.name}" (${skill.slug}) 内容文件未找到`)
        return null
      }
      return {
        name: skill.name,
        content,
        slug: skill.slug,
        loadedAt: Date.now()
      }
    } catch (err) {
      console.error(`[SkillLoader] 加载 Skill "${skill.name}" 失败:`, err)
      return null
    }
  }

  /** 读取 Skill 内容文件 */
  private async readSkillContent(slug: string): Promise<string | null> {
    const skillDir = join(this.skillsDir, slug)

    // 查找顺序：SKILL.md → README.md → 第一个 .md 文件
    const candidates = [
      join(skillDir, 'SKILL.md'),
      join(skillDir, 'README.md'),
    ]

    for (const filePath of candidates) {
      try {
        const content = await readFile(filePath, 'utf-8')
        if (content.trim()) return content.trim()
      } catch { /* 文件不存在，继续 */ }
    }

    // 最后尝试：找第一个 .md 文件
    try {
      const entries = await readdir(skillDir)
      const mdFile = entries.find(e => e.endsWith('.md'))
      if (mdFile) {
        const content = await readFile(join(skillDir, mdFile), 'utf-8')
        if (content.trim()) return content.trim()
      }
    } catch { /* ignore */ }

    return null
  }

  /** 根据 slug 直接加载单个 Skill 内容（供 load_skill 工具调用） */
  async loadSkillBySlug(slug: string): Promise<SkillContent | null> {
    try {
      const content = await this.readSkillContent(slug)
      if (!content) return null
      return { name: slug, content, slug, loadedAt: Date.now() }
    } catch {
      return null
    }
  }

  /** 从 index.json 加载 Skill 注册表 */
  async loadRegistry(): Promise<SkillRegistryEntry[]> {
    try {
      const indexPath = join(this.skillsDir, 'index.json')
      const raw = await readFile(indexPath, 'utf-8')
      const data = JSON.parse(raw)
      return data.skills || []
    } catch (err) {
      console.error('[SkillLoader] 加载 skills/index.json 失败:', err)
      return []
    }
  }
}
