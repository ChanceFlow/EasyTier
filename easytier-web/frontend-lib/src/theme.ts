import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
import 'vuetify/styles'
import '@mdi/font/css/materialdesignicons.css'

/**
 * EasyTier mobile-first theme.
 * Seed: signal teal (#1EC8A3) on OLED black — mesh-alive, not generic SaaS blue.
 */
const m3Light = {
  dark: false,
  colors: {
    primary: '#00875A',
    onPrimary: '#FFFFFF',
    primaryContainer: '#C8F5E8',
    onPrimaryContainer: '#04211A',
    secondary: '#4B5568',
    onSecondary: '#FFFFFF',
    secondaryContainer: '#E2E8F0',
    onSecondaryContainer: '#1E293B',
    tertiary: '#0284C7',
    onTertiary: '#FFFFFF',
    tertiaryContainer: '#DBE8FF',
    onTertiaryContainer: '#0A1F4A',
    error: '#E11D48',
    onError: '#FFFFFF',
    errorContainer: '#FFE1E6',
    onErrorContainer: '#4C0519',
    surface: '#FFFFFF',
    onSurface: '#0F1720',
    surfaceVariant: '#E8EDF4',
    onSurfaceVariant: '#5B6578',
    surfaceContainerLowest: '#FFFFFF',
    surfaceContainerLow: '#F8FAFC',
    surfaceContainer: '#F1F5F9',
    surfaceContainerHigh: '#E2E8F0',
    surfaceContainerHighest: '#CBD5E1',
    outline: '#94A3B8',
    outlineVariant: '#CBD5E1',
    inverseSurface: '#0F172A',
    inverseOnSurface: '#F8FAFC',
    inversePrimary: '#00F2B6',
    shadow: '#000000',
    scrim: '#000000',
    background: '#F8FAFC',
    onBackground: '#0F1720',
    surfaceBright: '#FFFFFF',
    surfaceDim: '#E2E8F0',
    success: '#00875A',
    onSuccess: '#FFFFFF',
    successContainer: '#C8F5E8',
    onSuccessContainer: '#04211A',
    warning: '#B45309',
    onWarning: '#FFFFFF',
    warningContainer: '#FEF3C7',
    onWarningContainer: '#78350F',
    info: '#0369A1',
    onInfo: '#FFFFFF',
    infoContainer: '#E0F2FE',
    onInfoContainer: '#0369A1',
  },
}

const m3Dark = {
  dark: true,
  colors: {
    primary: '#00F2B6',
    onPrimary: '#04211A',
    primaryContainer: '#054A38',
    onPrimaryContainer: '#C8F5E8',
    secondary: '#8E99AF',
    onSecondary: '#111622',
    secondaryContainer: '#1E273A',
    onSecondaryContainer: '#E2E8F0',
    tertiary: '#00B4D8',
    onTertiary: '#041628',
    tertiaryContainer: '#0A3246',
    onTertiaryContainer: '#CAF0F8',
    error: '#FF4D6D',
    onError: '#3B0608',
    errorContainer: '#5C1220',
    onErrorContainer: '#FFD5DC',
    surface: '#0D111A',
    onSurface: '#F3F6FA',
    surfaceVariant: '#151B28',
    onSurfaceVariant: '#8E99AF',
    surfaceContainerLowest: '#06080D',
    surfaceContainerLow: '#090D14',
    surfaceContainer: '#0D111A',
    surfaceContainerHigh: '#151B28',
    surfaceContainerHighest: '#1F283B',
    outline: '#5D6880',
    outlineVariant: '#202B3F',
    inverseSurface: '#F3F6FA',
    inverseOnSurface: '#0D111A',
    inversePrimary: '#00875A',
    shadow: '#000000',
    scrim: '#000000',
    background: '#07090E',
    onBackground: '#F3F6FA',
    surfaceBright: '#1F283B',
    surfaceDim: '#07090E',
    success: '#00F2B6',
    onSuccess: '#04211A',
    successContainer: '#054A38',
    onSuccessContainer: '#C8F5E8',
    warning: '#FFB703',
    onWarning: '#2A1C00',
    warningContainer: '#543B00',
    onWarningContainer: '#FFE8B5',
    info: '#00B4D8',
    onInfo: '#041628',
    infoContainer: '#0A3246',
    onInfoContainer: '#CAF0F8',
  },
}

function initialTheme(): 'm3Light' | 'm3Dark' {
  try {
    const stored = localStorage.getItem('et-theme')
    if (stored === 'm3Light' || stored === 'm3Dark') {
      return stored
    }
    if (window.matchMedia?.('(prefers-color-scheme: light)').matches) {
      return 'm3Light'
    }
  }
  catch {
    // happy-dom / SSR
  }
  return 'm3Dark'
}

export const vuetify = createVuetify({
  components,
  directives,
  theme: {
    defaultTheme: initialTheme(),
    themes: {
      m3Light,
      m3Dark,
    },
  },
  defaults: {
    global: {
      density: 'comfortable',
    },
    VBtn: {
      rounded: 'lg',
      textTransform: 'none',
    },
    VCard: {
      rounded: 'lg',
    },
    VTextField: {
      variant: 'outlined',
      density: 'comfortable',
      hideDetails: 'auto',
    },
    VSelect: {
      variant: 'outlined',
      density: 'comfortable',
      hideDetails: 'auto',
    },
    VCombobox: {
      variant: 'outlined',
      density: 'comfortable',
      hideDetails: 'auto',
    },
    VTextarea: {
      variant: 'outlined',
      hideDetails: 'auto',
    },
    VSwitch: {
      inset: true,
      color: 'primary',
      hideDetails: true,
      density: 'compact',
    },
    VDialog: {
      rounded: 'xl',
    },
    VList: {
      rounded: 'lg',
    },
    VBottomSheet: {
      inset: false,
    },
  },
})

export default vuetify
