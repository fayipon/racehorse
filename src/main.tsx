import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { isCup } from './game'
import { applyLocale, detectLocale, loadMessages, rememberLocale } from './i18n'
import { I18nProvider } from './I18nProvider'
import { parseRoute, showRoute } from './route'
import { bootSchedule, startScheduleRefresh } from './schedule'

// Each cup has its own page, marked on <body>; only a cup page loads the race.
// The address names the language; one without it opens in the last language
// used, or the browser's, and gains it.
// The page, its language's words and the race schedule load side by side.
const root = createRoot(document.getElementById('root')!)
const cup = document.body.dataset.cup
const routed = parseRoute(location.pathname).locale
const locale = routed ?? detectLocale()
if (routed) rememberLocale(routed)
showRoute(locale, isCup(cup) ? cup : undefined)
applyLocale(locale)
const page = isCup(cup)
  ? import('./App.tsx').then(({ default: App }) => <App cup={cup} />)
  : import('./Lobby.tsx').then(({ default: Lobby }) => <Lobby />)
void Promise.all([page, loadMessages(locale), bootSchedule()]).then(([element, messages]) => { startScheduleRefresh(); root.render(<StrictMode><I18nProvider locale={locale} messages={messages}>{element}</I18nProvider></StrictMode>) })
