import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { whoami } from './api'

const mount = () =>
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )

// Our own @p comes from the nexus, and one component needs it the first
// time it renders: the reply composer drops us from its default recipient
// list, and seeding that list is a once-per-thread event that no later
// value can correct. So resolve it before the first paint rather than
// after — one same-origin request against a route the page was just
// served from.
//
// `.catch` and not `.finally` alone: if the ship cannot say who it is,
// the app still mounts (the inbox will render its own error) rather than
// showing a permanently blank page.
whoami().catch((e) => { console.error(e) }).then(mount)
