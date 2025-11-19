// Test hook to verify module worker bundling with esbuild

export default {
  mounted() {
    console.log('Test worker hook mounted');

    // This is the pattern we'll use for the Whisper worker
    // esbuild should bundle this correctly
    try {
      this.worker = new Worker(
        new URL('../workers/test_worker.js', import.meta.url),
        { type: 'module' }
      );

      this.worker.onmessage = (e) => {
        console.log('Received from worker:', e.data);
      };

      this.worker.onerror = (error) => {
        console.error('Worker error:', error);
      };

      // Test the worker
      this.worker.postMessage({
        type: 'ping',
        data: { timestamp: Date.now() }
      });

      console.log('Test worker created successfully');
    } catch (error) {
      console.error('Failed to create worker:', error);
    }
  },

  destroyed() {
    if (this.worker) {
      this.worker.terminate();
    }
  }
}
