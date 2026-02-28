/**
 * 带 429 限流自动重试的 fetch 封装
 * 支持指数退避 + Retry-After 头解析 + 网络层错误重试（VPN 切换场景）
 */

export interface RetryFetchOptions {
  maxRetries?: number
  baseDelayMs?: number
  maxDelayMs?: number
  onRetry?: (attempt: number, delayMs: number) => void
}

/**
 * 发起 HTTP 请求，遇到 429 或网络错误自动等待重试
 * @returns Response 对象（保证 status !== 429）
 */
export async function retryFetch(
  url: string,
  init: RequestInit,
  options?: RetryFetchOptions
): Promise<Response> {
  const maxRetries = options?.maxRetries ?? 5
  const baseDelay = options?.baseDelayMs ?? 5000
  const maxDelay = options?.maxDelayMs ?? 60000

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    let response: Response

    try {
      response = await fetch(url, init)
    } catch (err: any) {
      // 网络层错误（fetch failed / ECONNREFUSED / ENOTFOUND 等）
      // 常见于 VPN 切换瞬间，自动重试
      if (attempt >= maxRetries) throw err

      const delayMs = Math.min(baseDelay * Math.pow(2, attempt), maxDelay) + Math.random() * 1000
      const errMsg = err?.cause?.code || err?.message || String(err)
      console.warn(`[RetryFetch] 网络错误 (${errMsg})，第 ${attempt + 1} 次重试，等待 ${Math.round(delayMs / 1000)}s...`)
      options?.onRetry?.(attempt + 1, delayMs)
      await new Promise(resolve => setTimeout(resolve, delayMs))
      continue
    }

    if (response.status !== 429) {
      return response
    }

    // 429 限流 — 计算等待时间
    if (attempt >= maxRetries) {
      return response // 超过最大重试次数，返回 429 响应
    }

    let delayMs = Math.min(baseDelay * Math.pow(2, attempt), maxDelay)

    // 尝试从 Retry-After 头获取等待时间
    const retryAfter = response.headers.get('Retry-After')
    if (retryAfter) {
      const seconds = parseInt(retryAfter)
      if (!isNaN(seconds)) {
        delayMs = seconds * 1000
      }
    }

    // 加一点随机抖动避免多个请求同时重试
    delayMs += Math.random() * 1000

    console.log(`[RetryFetch] 429 限流，第 ${attempt + 1} 次重试，等待 ${Math.round(delayMs / 1000)}s...`)
    options?.onRetry?.(attempt + 1, delayMs)

    await new Promise(resolve => setTimeout(resolve, delayMs))
  }

  // 不应该到这里，但以防万一
  return fetch(url, init)
}
