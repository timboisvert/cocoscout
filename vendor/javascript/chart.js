// Chart.js ESM wrapper for importmaps
// Import the UMD build which sets window.Chart
import "chart.umd.js";

// Export Chart from global
const Chart = window.Chart;
export { Chart };
export default Chart;
