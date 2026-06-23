import { useT } from '../i18n'

export function Hero() {
  const t = useT()
  return (
    <div>
      <h1>{ t('hero.title') }</h1>
      <button>{ t('hero.cta') }</button>
    </div>
  )
}

export function Footer() {
  const t = useT('common')
  return <span>{ t('ok') }</span>
}
