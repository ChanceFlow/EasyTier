import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
import 'vuetify/styles'
import '@mdi/font/css/materialdesignicons.css'

/**
 * EasyTier mobile-first theme — design system v2 "Instrument".
 *
 * Vuetify generates `--v-theme-*` CSS variables from these literals, so every
 * value here is a literal hex copy of a `tokens.css` semantic token. Keep the
 * two in sync; the token names are named in the comments.
 * Contrast of every on/container pair was verified against the tokens:
 * text pairs >= 4.5:1, `outline` is a control border and clears the 3:1 of
 * WCAG 1.4.11 (`--et-control-border` on `--et-surface-1`).
 */
const m3Light = {
  dark: false,
  colors: {
    primary: '#00795F',                 // --et-accent
    onPrimary: '#FFFFFF',               // --et-on-accent
    primaryContainer: '#D6F2EA',        // --et-accent-quiet
    onPrimaryContainer: '#00795F',      // --et-accent on quiet
    secondary: '#5E6A80',               // --et-neutral
    onSecondary: '#FFFFFF',             // on --et-neutral (5.46:1)
    secondaryContainer: '#EEF2F7',      // --et-neutral-quiet
    onSecondaryContainer: '#0D1420',    // --et-text
    tertiary: '#0B5FA5',                // --et-info
    onTertiary: '#FFFFFF',              // --et-on-info
    tertiaryContainer: '#DBEAFE',       // --et-info-quiet
    onTertiaryContainer: '#0B5FA5',     // --et-info on quiet
    error: '#B3123A',                   // --et-danger
    onError: '#FFFFFF',                 // --et-on-danger
    errorContainer: '#FDE2E8',          // --et-danger-quiet
    onErrorContainer: '#B3123A',        // --et-danger on quiet
    surface: '#FFFFFF',                 // --et-surface-1
    onSurface: '#0D1420',               // --et-text
    surfaceVariant: '#EEF2F7',          // --et-surface-2
    onSurfaceVariant: '#46536B',        // --et-text-2
    surfaceContainerLowest: '#E8EDF4',  // --et-surface-sunken
    surfaceContainerLow: '#FFFFFF',     // --et-surface-1
    surfaceContainer: '#FFFFFF',        // --et-surface-1
    surfaceContainerHigh: '#EEF2F7',    // --et-surface-2
    surfaceContainerHighest: '#FFFFFF', // --et-surface-3
    outline: '#838B99',                 // --et-control-border (>=3:1)
    outlineVariant: '#CFD0D2',          // --et-border-strong over --et-surface-1
    inverseSurface: '#0D1420',          // --et-text
    inverseOnSurface: '#F5F7FA',        // --et-bg
    inversePrimary: '#2DE0B0',          // dark --et-accent
    shadow: '#000000',
    scrim: '#000000',
    background: '#F5F7FA',              // --et-bg
    onBackground: '#0D1420',            // --et-text
    surfaceBright: '#FFFFFF',           // --et-surface-1
    surfaceDim: '#E8EDF4',              // --et-surface-sunken
    success: '#00795F',                 // --et-accent
    onSuccess: '#FFFFFF',               // --et-on-accent
    successContainer: '#D6F2EA',        // --et-accent-quiet
    onSuccessContainer: '#00795F',
    warning: '#8A5300',                 // --et-warn
    onWarning: '#FFFFFF',               // --et-on-warn
    warningContainer: '#FDF0D5',        // --et-warn-quiet
    onWarningContainer: '#8A5300',
    info: '#0B5FA5',                    // --et-info
    onInfo: '#FFFFFF',                  // --et-on-info
    infoContainer: '#DBEAFE',           // --et-info-quiet
    onInfoContainer: '#0B5FA5',
  },
}

const m3Dark = {
  dark: true,
  colors: {
    primary: '#2DE0B0',                 // --et-accent
    onPrimary: '#04211A',               // --et-on-accent
    primaryContainer: '#123A31',        // --et-accent-quiet
    onPrimaryContainer: '#2DE0B0',      // --et-accent on quiet
    secondary: '#8A97AD',               // --et-neutral
    onSecondary: '#0A0E14',             // --et-bg (6.55:1 on neutral)
    secondaryContainer: '#1A2130',      // --et-neutral-quiet
    onSecondaryContainer: '#E9EEF6',    // --et-text
    tertiary: '#5AB0FF',                // --et-info
    onTertiary: '#041628',              // --et-on-info
    tertiaryContainer: '#10263A',       // --et-info-quiet
    onTertiaryContainer: '#5AB0FF',     // --et-info on quiet
    error: '#FF6B87',                   // --et-danger
    onError: '#3B0608',                 // --et-on-danger
    errorContainer: '#35131C',          // --et-danger-quiet
    onErrorContainer: '#FF6B87',        // --et-danger on quiet
    surface: '#111823',                 // --et-surface-1
    onSurface: '#E9EEF6',               // --et-text
    surfaceVariant: '#18202E',          // --et-surface-2
    onSurfaceVariant: '#9BA8BC',        // --et-text-2
    surfaceContainerLowest: '#070A10',  // --et-surface-sunken
    surfaceContainerLow: '#111823',     // --et-surface-1
    surfaceContainer: '#111823',        // --et-surface-1
    surfaceContainerHigh: '#18202E',    // --et-surface-2
    surfaceContainerHighest: '#1F2938', // --et-surface-3
    outline: '#6E7A8C',                 // --et-control-border (>=3:1)
    outlineVariant: '#373D46',          // --et-border-strong over --et-surface-1
    inverseSurface: '#E9EEF6',          // --et-text
    inverseOnSurface: '#0A0E14',        // --et-bg
    inversePrimary: '#00795F',          // light --et-accent
    shadow: '#000000',
    scrim: '#000000',
    background: '#0A0E14',              // --et-bg
    onBackground: '#E9EEF6',            // --et-text
    surfaceBright: '#1F2938',           // --et-surface-3
    surfaceDim: '#070A10',              // --et-surface-sunken
    success: '#2DE0B0',                 // --et-accent
    onSuccess: '#04211A',               // --et-on-accent
    successContainer: '#123A31',        // --et-accent-quiet
    onSuccessContainer: '#2DE0B0',
    warning: '#FFB020',                 // --et-warn
    onWarning: '#2A1C00',               // --et-on-warn
    warningContainer: '#33260A',        // --et-warn-quiet
    onWarningContainer: '#FFB020',
    info: '#5AB0FF',                    // --et-info
    onInfo: '#041628',                  // --et-on-info
    infoContainer: '#10263A',           // --et-info-quiet
    onInfoContainer: '#5AB0FF',
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
