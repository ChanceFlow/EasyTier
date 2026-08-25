import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
import 'vuetify/styles'
import '@mdi/font/css/materialdesignicons.css'

/**
 * EasyTier Material 3 theme — shared across the desktop GUI, web frontend
 * and config generator. Seed color: EasyTier blue (#3B82F6).
 */
const m3Light = {
  dark: false,
  colors: {
    // M3 core roles (light)
    primary: '#3B82F6',
    onPrimary: '#FFFFFF',
    primaryContainer: '#D9E4FF',
    onPrimaryContainer: '#001945',
    secondary: '#565F71',
    onSecondary: '#FFFFFF',
    secondaryContainer: '#DBE2F9',
    onSecondaryContainer: '#131C2B',
    tertiary: '#006684',
    onTertiary: '#FFFFFF',
    tertiaryContainer: '#BDE9FF',
    onTertiaryContainer: '#001F2A',
    error: '#BA1A1A',
    onError: '#FFFFFF',
    errorContainer: '#FFDAD6',
    onErrorContainer: '#410002',
    surface: '#F9F9FF',
    onSurface: '#191B20',
    surfaceVariant: '#E1E2EC',
    onSurfaceVariant: '#44474F',
    surfaceContainerLowest: '#FFFFFF',
    surfaceContainerLow: '#F3F3FA',
    surfaceContainer: '#EDEDF4',
    surfaceContainerHigh: '#E7E8EF',
    surfaceContainerHighest: '#E2E2E9',
    outline: '#74777F',
    outlineVariant: '#C4C6D0',
    inverseSurface: '#2E3036',
    inverseOnSurface: '#F1F0F7',
    inversePrimary: '#A9C8FF',
    shadow: '#000000',
    scrim: '#000000',
    // Vuetify semantic roles mapped onto the M3 palette
    background: '#F1F5F9',
    onBackground: '#191B20',
    surfaceBright: '#F9F9FF',
    surfaceDim: '#D9D9E0',
    success: '#10B981',
    onSuccess: '#FFFFFF',
    successContainer: '#B7F4D8',
    onSuccessContainer: '#00210E',
    warning: '#F59E0B',
    onWarning: '#FFFFFF',
    warningContainer: '#FFDEB0',
    onWarningContainer: '#2D1600',
    info: '#0EA5E9',
    onInfo: '#FFFFFF',
    infoContainer: '#CCE8FF',
    onInfoContainer: '#001D31',
  },
}

const m3Dark = {
  dark: true,
  colors: {
    primary: '#A9C8FF',
    onPrimary: '#002E6B',
    primaryContainer: '#00439C',
    onPrimaryContainer: '#D9E4FF',
    secondary: '#BFC6DA',
    onSecondary: '#293140',
    secondaryContainer: '#3F4758',
    onSecondaryContainer: '#DBE2F9',
    tertiary: '#6CD2FA',
    onTertiary: '#003546',
    tertiaryContainer: '#004D66',
    onTertiaryContainer: '#BDE9FF',
    error: '#FFB4AB',
    onError: '#690005',
    errorContainer: '#93000A',
    onErrorContainer: '#FFDAD6',
    surface: '#111318',
    onSurface: '#E2E2E9',
    surfaceVariant: '#44474F',
    onSurfaceVariant: '#C4C6D0',
    surfaceContainerLowest: '#0C0E13',
    surfaceContainerLow: '#191B20',
    surfaceContainer: '#1D1F25',
    surfaceContainerHigh: '#27292F',
    surfaceContainerHighest: '#32343A',
    outline: '#8E9099',
    outlineVariant: '#44474F',
    inverseSurface: '#E2E2E9',
    inverseOnSurface: '#2E3036',
    inversePrimary: '#3B82F6',
    shadow: '#000000',
    scrim: '#000000',
    background: '#0F1116',
    onBackground: '#E2E2E9',
    surfaceBright: '#393B41',
    surfaceDim: '#111318',
    success: '#5ED6A5',
    onSuccess: '#003824',
    successContainer: '#005238',
    onSuccessContainer: '#B7F4D8',
    warning: '#FFC668',
    onWarning: '#4A2800',
    warningContainer: '#6F3C00',
    onWarningContainer: '#FFDEB0',
    info: '#6FCFFF',
    onInfo: '#00344C',
    infoContainer: '#004C6B',
    onInfoContainer: '#CCE8FF',
  },
}

export const vuetify = createVuetify({
  components,
  directives,
  theme: {
    defaultTheme: 'm3Light',
    themes: {
      m3Light,
      m3Dark,
    },
  },
  defaults: {
    global: {
      // Slightly larger touch targets for mobile-first
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
      density: 'compact',
      hideDetails: 'auto',
    },
    VSelect: {
      variant: 'outlined',
      density: 'compact',
      hideDetails: 'auto',
    },
    VCombobox: {
      variant: 'outlined',
      density: 'compact',
      hideDetails: 'auto',
    },
    VTextarea: {
      variant: 'outlined',
      hideDetails: 'auto',
    },
    VDialog: {
      rounded: 'xl',
    },
    VList: {
      rounded: 'lg',
    },
  },
})

export default vuetify
