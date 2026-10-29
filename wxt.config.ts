import { defineConfig } from 'wxt';

export default defineConfig({
  modules: ['@wxt-dev/module-vue'],
  manifest: {
    name: 'Cloudflare Billing Helper',
    description:
      'Cloudflare 可计费使用量页增强：免费额度进度、耗尽预警、用量预估与按应用拆分。所有数据仅在本地处理。',
    permissions: ['storage'],
    host_permissions: ['https://dash.cloudflare.com/*'],
  },
});
