// Simple test worker to verify module worker bundling works with esbuild

self.onmessage = (e) => {
  const { type, data } = e.data;

  if (type === 'ping') {
    self.postMessage({
      type: 'pong',
      data: { message: 'Worker is alive!', received: data }
    });
  }
};

console.log('Test worker loaded successfully');
