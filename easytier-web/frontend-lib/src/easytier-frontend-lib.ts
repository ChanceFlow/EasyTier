import './style.css'
// v2 设计令牌必须排在 style.css 之后：v1 的令牌也在 :root 与
// .v-theme--m3Light 里定义，同优先级下靠源码顺序决胜。tokens.css 同时
// 提供 v1 名字的兼容别名，所以旧代码不改也能立刻吃到 v2 的值。
import './tokens.css'

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
