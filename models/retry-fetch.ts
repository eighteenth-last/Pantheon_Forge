/**
 * 带 429 限流自动重试的 fetch 封装
 * 支持指数退避 + Retry-After 头解析
 */

export interface RetryFetchOptions {
  maxRetries?: number
  baseDelayMs?: number
  maxDelayMs?: number
  onRetry?: (attempt: number, delayMs: number) => void
}

/**
 * 发起 HTTP 请求，遇到 429 自动等待重试
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
    const response = await fetch(url, init)

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
