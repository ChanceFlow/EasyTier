import './style.css'

import type { App } from 'vue';
import { Config, Status, ConfigEditDialog, RemoteManagement } from "./components";
import HumanEvent from './components/HumanEvent.vue';

import { vuetify } from './theme';

import I18nUtils from './modules/i18n'
import * as NetworkTypes from './types/network'

import * as Api from './modules/api';
import * as Utils from './modules/utils';

export default {
    install: (app: App): void => {
        app.use(I18nUtils.i18n, { useScope: 'global' })
        app.use(vuetify)

        app.component('Config', Config);
        app.component('ConfigEditDialog', ConfigEditDialog);
        app.component('Status', Status);
        app.component('HumanEvent', HumanEvent);
        app.component('RemoteManagement', RemoteManagement);
    }
};

export { Config, ConfigEditDialog, RemoteManagement, Status, HumanEvent, I18nUtils, NetworkTypes, Api, Utils };
export { vuetify };
