import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

/**
 * Phone-first copy that has no key in the frontend-lib locales yet.
 *
 * `t(key, default)` (vue-i18n composer) returns the default message while the
 * key is missing — so once `hero.*` keys land in the lib's cn/en.yaml they
 * automatically take precedence over the inline fallback. The fallback itself
 * is picked from the *current* locale, so the UI is never half-translated.
 */
export function usePhoneText() {
  const { t, locale } = useI18n()

  const isZh = computed(() => {
    const lang = String(locale.value ?? '')
    return lang === 'cn' || lang.startsWith('zh')
  })

  function pt(key: string, zh: string, en: string): string {
    return t(key, isZh.value ? zh : en)
  }

  return { pt, isZh }
}
