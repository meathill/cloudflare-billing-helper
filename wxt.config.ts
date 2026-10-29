import { defineConfig } from 'wxt';

export default defineConfig({
  modules: ['@wxt-dev/module-vue'],
  manifest: {
    // 名称/描述走 Chrome i18n（public/_locales），随浏览器界面语言切换
    name: '__MSG_extName__',
    description: '__MSG_extDescription__',
    default_locale: 'en',
    permissions: ['storage'],
    host_permissions: ['https://dash.cloudflare.com/*'],
  },
});
