import { defineStore } from 'pinia'
import { ref } from 'vue'

export interface ServiceItem {
  serviceId: string
  command: string
  status: string
  termId: number
}

export const useTaskStore = defineStore('tasks', () => {
  const services = ref<ServiceItem[]>([])

  /** 刷新服务列表 */
  async function refreshServices() {
    try {
      const list = await window.api.service.list()
      services.value = list.map((s: any) => ({
        serviceId: s.serviceId,
        command: s.command,
        status: s.status,
        termId: s.termId
      }))
    } catch { /* ignore */ }
  }

  return { services, refreshServices }
})
