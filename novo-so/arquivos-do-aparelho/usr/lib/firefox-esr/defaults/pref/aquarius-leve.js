// Firefox mais leve para o GPS (Allwinner A10 de 1 GHz, 512 MB). Medido com aquarius-bench-tablet (06/11/2026).
// Menos processos: um processo de conteudo so (sem isolamento por site).
pref("fission.autostart", false);
pref("dom.ipc.processCount", 1);
pref("dom.ipc.processCount.webIsolated", 1);
pref("dom.ipc.processPrelaunch.enabled", false);
pref("browser.preferences.defaultPerformanceSettings.enabled", false);
pref("browser.tabs.unloadOnLowMemory", true);
// Abertura sem paginas extras nem tela de boas-vindas.
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.aboutwelcome.enabled", false);
pref("browser.startup.preXulSkeletonUI", false);
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("extensions.pocket.enabled", false);
pref("browser.ml.enable", false);
pref("browser.ml.chat.enabled", false);
// Nada de trabalho em segundo plano que nao serve aqui.
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("app.normandy.enabled", false);
pref("app.shield.optoutstudies.enabled", false);
pref("browser.discovery.enabled", false);
pref("browser.sessionstore.interval", 60000);
// Menos desenho: sem rolagem suave nem animacoes.
pref("general.smoothScroll", false);
pref("toolkit.cosmeticAnimations.enabled", false);
