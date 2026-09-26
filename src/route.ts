import { isCup, type CupId } from './game'
import { LOCALES, type Locale } from './locale'

// Every address names its language: {base}{locale}/ is the lobby and
// {base}{locale}/{cup}/ a cup, as /racehorse/en/sunny/. A shared link opens in
// the language it was shared in.
export interface Route { locale?: Locale; cup?: CupId }

// The language is matched in any letter case; an address without one has none.
export function parseRoute(pathname: string, base = import.meta.env.BASE_URL): Route {
  const rest = pathname.startsWith(base) ? pathname.slice(base.length) : pathname.replace(/^\//, '')
  const parts = rest.split('/').filter(Boolean)
  const locale = LOCALES.find(code => code.toLowerCase() === parts[0]?.toLowerCase())
  const cup = parts[locale ? 1 : 0]
  return { locale, cup: isCup(cup) ? cup : undefined }
}

export const routePath = (locale: Locale, cup?: CupId, base = import.meta.env.BASE_URL) => `${base}${locale}/${cup ? `${cup}/` : ''}`

// Points the address bar at a page in a language, keeping its query and anchor.
export function showRoute(locale: Locale, cup?: CupId) {
  const path = routePath(locale, cup)
  if (location.pathname !== path) history.replaceState(history.state, '', path + location.search + location.hash)
}
