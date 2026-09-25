import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { isCup } from './game'

// Each cup has its own page, marked on <body>; only a cup page loads the race.
const root = createRoot(document.getElementById('root')!)
const cup = document.body.dataset.cup
if (isCup(cup)) void import('./App.tsx').then(({ default: App }) => root.render(<StrictMode><App cup={cup} /></StrictMode>))
else void import('./Lobby.tsx').then(({ default: Lobby }) => root.render(<StrictMode><Lobby /></StrictMode>))
