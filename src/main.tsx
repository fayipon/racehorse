import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { isCup } from './game'
import { applyLocale, detectLocale, loadMessages } from './i18n'
import { I18nProvider } from './I18nProvider'

// Each cup has its own page, marked on <body>; only a cup page loads the race.
// The page and its language's words load side by side.
const root = createRoot(document.getElementById('root')!)
const cup = document.body.dataset.cup
const locale = detectLocale()
applyLocale(locale)
const page = isCup(cup)
  ? import('./App.tsx').then(({ default: App }) => <App cup={cup} />)
  : import('./Lobby.tsx').then(({ default: Lobby }) => <Lobby />)
void Promise.all([page, loadMessages(locale)]).then(([element, messages]) => root.render(<StrictMode><I18nProvider locale={locale} messages={messages}>{element}</I18nProvider></StrictMode>))
