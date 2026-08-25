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
    primary: '#0F9D7E',
    onPrimary: '#FFFFFF',
    primaryContainer: '#C8F5E8',
    onPrimaryContainer: '#04211A',
    secondary: '#4B5568',
    onSecondary: '#FFFFFF',
    secondaryContainer: '#E2E8F0',
    onSecondaryContainer: '#1E293B',
    tertiary: '#2563EB',
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
    surfaceContainerLow: '#F5F7FA',
    surfaceContainer: '#EEF1F6',
    surfaceContainerHigh: '#E4E9F0',
    surfaceContainerHighest: '#DCE3EE',
    outline: '#8B93A4',
    outlineVariant: '#D5DCE6',
    inverseSurface: '#1B2030',
    inverseOnSurface: '#F3F5F7',
    inversePrimary: '#1EC8A3',
    shadow: '#000000',
    scrim: '#000000',
    background: '#EEF1F6',
    onBackground: '#0F1720',
    surfaceBright: '#FFFFFF',
    surfaceDim: '#DCE3EE',
    success: '#0F9D7E',
    onSuccess: '#FFFFFF',
    successContainer: '#C8F5E8',
    onSuccessContainer: '#04211A',
    warning: '#C98500',
    onWarning: '#FFFFFF',
    warningContainer: '#FFE8B5',
    onWarningContainer: '#3D2800',
    info: '#2563EB',
    onInfo: '#FFFFFF',
    infoContainer: '#DBE8FF',
    onInfoContainer: '#0A1F4A',
  },
}

const m3Dark = {
  dark: true,
  colors: {
    primary: '#1EC8A3',
    onPrimary: '#04211A',
    primaryContainer: '#0B4F40',
    onPrimaryContainer: '#C8F5E8',
    secondary: '#B4BCCE',
    onSecondary: '#1B2030',
    secondaryContainer: '#2A3144',
    onSecondaryContainer: '#E2E8F0',
    tertiary: '#5AA7FF',
    onTertiary: '#041628',
    tertiaryContainer: '#0F2A4A',
    onTertiaryContainer: '#DBE8FF',
    error: '#FF5A5F',
    onError: '#3B0608',
    errorContainer: '#6B1216',
    onErrorContainer: '#FFD5D6',
    surface: '#12151C',
    onSurface: '#F3F5F7',
    surfaceVariant: '#1B2030',
    onSurfaceVariant: '#8B93A7',
    surfaceContainerLowest: '#07080A',
    surfaceContainerLow: '#0E1116',
    surfaceContainer: '#12151C',
    surfaceContainerHigh: '#1B2030',
    surfaceContainerHighest: '#242B3D',
    outline: '#5C6478',
    outlineVariant: '#2A3144',
    inverseSurface: '#F3F5F7',
    inverseOnSurface: '#12151C',
    inversePrimary: '#0F9D7E',
    shadow: '#000000',
    scrim: '#000000',
    background: '#07080A',
    onBackground: '#F3F5F7',
    surfaceBright: '#242B3D',
    surfaceDim: '#07080A',
    success: '#1EC8A3',
    onSuccess: '#04211A',
    successContainer: '#0B4F40',
    onSuccessContainer: '#C8F5E8',
    warning: '#F5B942',
    onWarning: '#2A1C00',
    warningContainer: '#5C4300',
    onWarningContainer: '#FFE8B5',
    info: '#5AA7FF',
    onInfo: '#041628',
    infoContainer: '#0F2A4A',
    onInfoContainer: '#DBE8FF',
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
