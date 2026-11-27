{{flutter_js}}
{{flutter_build_config}}

const serviceWorkerVersion = {{flutter_service_worker_version}};
const intergalacticPushWorkerPath = 'intergalactic_push_service_worker.js';
const intergalacticPushWorkerScope = 'push-notifications/';

function registerIntergalacticPushWorker() {
  if (!('serviceWorker' in navigator)) {
    return;
  }

  navigator.serviceWorker.register(intergalacticPushWorkerPath, {
    scope: intergalacticPushWorkerScope,
  }).catch((error) => {
    console.warn('Failed to register Inter Galactic push worker', error);
  });
}

registerIntergalacticPushWorker();

_flutter.loader.load({
  serviceWorker: {
    serviceWorkerVersion,
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    window.removeSplashFromWeb?.();
  }
});
