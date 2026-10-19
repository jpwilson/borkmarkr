/**
 * PostHog Analytics Configuration
 * 
 * This file can be generated at build time with environment variables,
 * or manually edited to set your PostHog project configuration.
 * 
 * For GitHub Pages deployment with GitHub Actions:
 * - Set POSTHOG_KEY and POSTHOG_HOST as repository secrets
 * - Use a workflow to generate this file during deployment
 * 
 * For local testing or manual deployment:
 * - Copy this file and set your actual values below
 * - The site will work without PostHog if apiKey is not set
 */

window.__POSTHOG_CONFIG__ = {
  // Your PostHog project API key (starts with 'phc_')
  // Set this from environment: process.env.POSTHOG_KEY or process.env.NEXT_PUBLIC_POSTHOG_KEY
  apiKey: '',
  
  // PostHog API host (defaults to US Cloud)
  // Set this from environment: process.env.POSTHOG_HOST
  apiHost: 'https://us.i.posthog.com',
  
  // Optional: Custom configuration
  options: {
    // PostHog SDK defaults version
    defaults: '2025-05-24',
    
    // Disable session recording if needed
    // disable_session_recording: false,
    
    // Mask all text content in recordings (privacy)
    // session_recording: {
    //   maskAllInputs: true,
    //   maskTextSelector: '*'
    // }
  }
};
