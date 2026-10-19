/**
 * PostHog Analytics Initialization
 * 
 * Initializes PostHog analytics if configured. The site works normally
 * without PostHog if the API key is not set.
 * 
 * Tracks:
 * - Page views (automatic)
 * - Sign up / Sign in events
 * - Bookmark saves
 * - Search usage
 * 
 * Privacy:
 * - No PII beyond user ID
 * - Form inputs are not recorded
 * - Opt-out available via ?internal=1 URL parameter
 */

(function() {
  'use strict';
  
  // Check if PostHog config is available
  var config = window.__POSTHOG_CONFIG__;
  
  if (!config || !config.apiKey || config.apiKey.trim() === '') {
    // No PostHog configured - site works normally without analytics
    console.info('PostHog analytics not configured (missing API key). Site running without analytics.');
    
    // Provide no-op stub for any code that might call posthog
    window.posthog = {
      init: function() {},
      capture: function() {},
      identify: function() {},
      reset: function() {},
      opt_in_capturing: function() {},
      opt_out_capturing: function() {},
      has_opted_out_capturing: function() { return true; }
    };
    
    return;
  }
  
  // Load PostHog snippet
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
  
  // Initialize PostHog with config
  var initOptions = Object.assign({
    api_host: config.apiHost || 'https://us.i.posthog.com'
  }, config.options || {});
  
  posthog.init(config.apiKey, initOptions);
  
  // Internal device opt-out: visit /?internal=1 once to exclude your device
  // from analytics; /?internal=0 to undo
  try {
    var urlParams = new URLSearchParams(window.location.search);
    var internalParam = urlParams.get('internal');
    
    if (internalParam === '1') {
      localStorage.setItem('bm.internal', '1');
      posthog.opt_out_capturing();
    } else if (internalParam === '0') {
      localStorage.removeItem('bm.internal');
      posthog.opt_in_capturing();
    } else if (localStorage.getItem('bm.internal')) {
      posthog.opt_out_capturing();
    }
  } catch (e) {
    console.warn('PostHog opt-out check failed:', e);
  }
  
  console.info('PostHog analytics initialized');
})();

/**
 * Analytics helper functions
 * Call these from your application code to track events
 */
window.bookmarkerAnalytics = {
  /**
   * Track a custom event
   * @param {string} eventName - Name of the event
   * @param {object} properties - Optional event properties (no PII!)
   */
  track: function(eventName, properties) {
    if (window.posthog && typeof window.posthog.capture === 'function') {
      posthog.capture(eventName, properties || {});
    }
  },
  
  /**
   * Identify a user (call after sign in/up)
   * @param {string} userId - User identifier (no email/name - just an ID)
   * @param {object} properties - Optional user properties (no PII!)
   */
  identify: function(userId, properties) {
    if (window.posthog && typeof window.posthog.identify === 'function') {
      posthog.identify(userId, properties || {});
    }
  },
  
  /**
   * Reset user identity (call on sign out)
   */
  reset: function() {
    if (window.posthog && typeof window.posthog.reset === 'function') {
      posthog.reset();
    }
  },
  
  // Convenience methods for common events
  
  trackSignUp: function(method) {
    this.track('sign_up', { method: method || 'unknown' });
  },
  
  trackSignIn: function(method) {
    this.track('sign_in', { method: method || 'unknown' });
  },
  
  trackBookmarkSaved: function(source, category) {
    this.track('bookmark_saved', {
      source: source || 'unknown',
      category: category || 'uncategorized'
    });
  },
  
  trackSearch: function(query) {
    // Don't send the actual query (privacy) - just that a search happened
    this.track('search', {
      hasQuery: !!(query && query.length > 0),
      queryLength: query ? query.length : 0
    });
  }
};
