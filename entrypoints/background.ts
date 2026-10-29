/** 后台 service worker：当前无重逻辑，保留用于未来跨页面消息/缓存清理。 */
import { defineBackground } from '#imports';

export default defineBackground(() => {
  // 预留：接收 content script 消息
  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === 'cfbh:ping') {
      return true;
    }
    return false;
  });
});
