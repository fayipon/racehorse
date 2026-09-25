import { describe, expect, it } from 'vitest'
import { HORSES } from './game'
import { loadMessages, LOCALES, matchLocale } from './i18n'

describe('languages', () => {
  it('maps browser tags to the five languages, English otherwise', () => {
    expect(matchLocale('zh-TW')).toBe('zh-TW')
    expect(matchLocale('zh-HK')).toBe('zh-TW')
    expect(matchLocale('zh-Hant')).toBe('zh-TW')
    expect(matchLocale('zh-CN')).toBe('zh-CN')
    expect(matchLocale('zh-Hans-SG')).toBe('zh-CN')
    expect(matchLocale('ja-JP')).toBe('ja')
    expect(matchLocale('pt-PT')).toBe('pt-BR')
    expect(matchLocale('en-GB')).toBe('en')
    expect(matchLocale('fr-FR')).toBeUndefined()
  })

  it('names every runner and fills every list in each language', async () => {
    const source = await loadMessages('zh-TW')
    for (const locale of LOCALES) {
      const m = await loadMessages(locale)
      expect(m.horses, locale).toHaveLength(HORSES.length)
      expect(m.horses.every(name => name.trim()), locale).toBe(true)
      expect(m.chat.people, locale).toHaveLength(source.chat.people.length)
      expect(m.chat.opening, locale).toHaveLength(source.chat.opening.length)
      expect(m.podium.places, locale).toHaveLength(3)
      expect(m.rules.steps, locale).toHaveLength(source.rules.steps.length)
      for (const [moment, lines] of Object.entries(m.chat.lines)) expect(lines.length, `${locale} ${moment}`).toBeGreaterThan(2)
      // Chat templates only use the runner placeholders the chat fills in.
      for (const line of Object.values(m.chat.lines).flat()) expect(line.replace(/\{(horse|leader|winner)\}/g, ''), locale).not.toMatch(/[{}]/)
    }
  })
})
