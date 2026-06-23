import { useTranslation } from 'react-i18next'

export function App() {
  const { t } = useTranslation('common')
  return <button>{ t('ok') }</button>
}
