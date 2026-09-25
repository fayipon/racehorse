import { createContext, useContext } from 'react'
import type { Messages } from './locales/zh-TW'

export type { Messages }
export const LOCALES = ['zh-TW', 'zh-CN', 'en', 'ja', 'pt-BR'] as const
export type Locale = typeof LOCALES[number]
// Each language names itself in the picker.
export const LOCALE_NAMES: Record<Locale, string> = { 'zh-TW': '繁體中文', 'zh-CN': '简体中文', en: 'English', ja: '日本語', 'pt-BR': 'Português (BR)' }
// The picker's label on narrow screens.
export const LOCALE_SHORT: Record<Locale, string> = { 'zh-TW': '繁中', 'zh-CN': '简中', en: 'EN', ja: '日本語', 'pt-BR': 'PT' }
export const isLocale = (value: unknown): value is Locale => typeof value === 'string' && (LOCALES as readonly string[]).includes(value)

export const LOCALE_KEY = 'racehorse-locale'
const loaders: Record<Locale, () => Promise<{ default: Messages }>> = {
  'zh-TW': () => import('./locales/zh-TW'),
  'zh-CN': () => import('./locales/zh-CN'),
  en: () => import('./locales/en'),
  ja: () => import('./locales/ja'),
  'pt-BR': () => import('./locales/pt-BR'),
}
export const loadMessages = async (locale: Locale) => (await loaders[locale]()).default

// A browser tag to one of ours: Chinese by script or region, then by language, else English.
export function matchLocale(tag: string): Locale | undefined {
  const lower = tag.toLowerCase()
  if (lower.startsWith('zh')) return /hans|cn|sg|my/.test(lower) ? 'zh-CN' : 'zh-TW'
  if (lower.startsWith('ja')) return 'ja'
  if (lower.startsWith('pt')) return 'pt-BR'
  if (lower.startsWith('en')) return 'en'
  return undefined
}
export function detectLocale(): Locale {
  try {
    const saved = localStorage.getItem(LOCALE_KEY)
    if (isLocale(saved)) return saved
  } catch { /* Storage may be blocked; fall back to the browser. */ }
  for (const tag of navigator.languages ?? [navigator.language]) {
    const match = matchLocale(tag)
    if (match) return match
  }
  return 'en'
}

// Latin text uses Outfit alone; Chinese and Japanese add the Noto face drawn for that script.
const CJK_FONTS: Partial<Record<Locale, string>> = { 'zh-TW': 'Noto Sans TC', 'zh-CN': 'Noto Sans SC', ja: 'Noto Sans JP' }
const HTML_LANG: Record<Locale, string> = { 'zh-TW': 'zh-Hant-TW', 'zh-CN': 'zh-Hans-CN', en: 'en', ja: 'ja', 'pt-BR': 'pt-BR' }
export function applyLocale(locale: Locale) {
  document.documentElement.lang = HTML_LANG[locale]
  // Latin words run wider than single Han characters; the stylesheet sizes a few labels by script.
  document.documentElement.dataset.script = CJK_FONTS[locale] ? 'cjk' : 'latin'
  const cjk = CJK_FONTS[locale]
  const families = [cjk && `family=${cjk.replaceAll(' ', '+')}:wght@400;500;600;700;800;900`, 'family=Outfit:wght@400;500;600;700;800;900'].filter(Boolean).join('&')
  const href = `https://fonts.googleapis.com/css2?${families}&display=swap`
  const current = [...document.querySelectorAll<HTMLLinkElement>('link[data-locale-font]')]
  if (current.some(link => link.href === href)) return setCjk(cjk)
  // Keep the old faces until the new sheet arrives, so switching never flashes a fallback font.
  const link = Object.assign(document.createElement('link'), { rel: 'stylesheet', href })
  link.dataset.localeFont = ''
  link.addEventListener('load', () => { current.forEach(old => old.remove()); setCjk(cjk) }, { once: true })
  link.addEventListener('error', () => setCjk(cjk), { once: true })
  document.head.append(link)
  if (!current.length) setCjk(cjk)
}
function setCjk(cjk: string | undefined) {
  document.documentElement.style.setProperty('--cjk-font', cjk ? `'${cjk}'` : 'sans-serif')
}

export interface I18n {
  locale: Locale
  m: Messages
  setLocale: (locale: Locale) => Promise<void>
  /** Whole numbers: chips, payouts, metres. */
  n: (value: number) => string
  /** Two decimals, as odds are quoted. */
  price: (value: number) => string
  time: (at: number) => string
  horse: (id: number) => string
  /** The racing name under a local one, or nothing when the local name already is it. */
  horseAlias: (id: number) => string | undefined
}
export const I18nContext = createContext<I18n | null>(null)
export function useI18n() {
  const value = useContext(I18nContext)
  if (!value) throw new Error('useI18n needs an I18nProvider')
  return value
}
