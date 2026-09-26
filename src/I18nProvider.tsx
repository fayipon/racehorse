import { useCallback, useMemo, useState, type ReactNode } from 'react'
import { HORSES } from './game'
import { applyLocale, I18nContext, loadMessages, rememberLocale, type I18n, type Locale, type Messages } from './i18n'
import { parseRoute, showRoute } from './route'

export function I18nProvider({ locale: initialLocale, messages: initialMessages, children }: { locale: Locale; messages: Messages; children: ReactNode }) {
  const [state, setState] = useState({ locale: initialLocale, m: initialMessages })
  const setLocale = useCallback(async (locale: Locale) => {
    const m = await loadMessages(locale)
    rememberLocale(locale)
    applyLocale(locale)
    showRoute(locale, parseRoute(location.pathname).cup)
    setState({ locale, m })
  }, [])
  const value = useMemo<I18n>(() => {
    const whole = new Intl.NumberFormat(state.locale)
    const decimal = new Intl.NumberFormat(state.locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    const clock = new Intl.DateTimeFormat(state.locale, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    return {
      ...state,
      setLocale,
      n: value => whole.format(value),
      price: value => decimal.format(value),
      time: at => clock.format(at),
      horse: id => state.m.horses[id - 1],
      horseAlias: id => state.m.horses[id - 1].toUpperCase() === HORSES[id - 1].en ? undefined : HORSES[id - 1].en,
    }
  }, [state, setLocale])
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}
