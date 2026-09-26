// The languages the site speaks, shared by the app and the build, which
// writes each page once per language.
export const LOCALES = ['zh-TW', 'zh-CN', 'en', 'ja', 'pt-BR'] as const
export type Locale = typeof LOCALES[number]
export const isLocale = (value: unknown): value is Locale => typeof value === 'string' && (LOCALES as readonly string[]).includes(value)
export const HTML_LANG: Record<Locale, string> = { 'zh-TW': 'zh-Hant-TW', 'zh-CN': 'zh-Hans-CN', en: 'en', ja: 'ja', 'pt-BR': 'pt-BR' }
