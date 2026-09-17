export function useTable() {
  const token = useCookie<string | null>('table_token', { maxAge: 60 * 60 * 24 * 7 })
  const number = useState<number | null>('table-number', () => null)

  async function resolve() {
    if (!token.value || number.value !== null) return
    try {
      const res = await $fetch<{ number: number }>('/api/core/table', { query: { t: token.value } })
      number.value = res.number
    } catch {
      token.value = null
    }
  }

  return { token, number, resolve }
}
