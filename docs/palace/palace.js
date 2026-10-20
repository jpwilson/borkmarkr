import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// ========================================
// Configuration & Constants
// ========================================

const TAXONOMY = [
  { id: 'ai', name: 'AI', hue: 256, subs: ['Prompting', 'Tools', 'Agents', 'Coding with AI', 'Image generation'] },
  { id: 'fitness', name: 'Fitness', hue: 152, subs: ['Running', 'Strength', 'Mobility', 'Yoga', 'HIIT'] },
  { id: 'recipes', name: 'Recipes', hue: 42, subs: ['Quick meals', 'Meal prep', 'Baking', 'Desserts', 'Vegetarian'] },
  { id: 'tech', name: 'Tech', hue: 197, subs: ['Gadgets', 'Phones', 'Laptops', 'Reviews', 'Smart home'] },
  { id: 'travel', name: 'Travel', hue: 202, subs: ['Destinations', 'Itineraries', 'Budget travel', 'Hotels', 'Packing'] },
  { id: 'business', name: 'Business', hue: 180, subs: ['Startups', 'Strategy', 'Finance', 'Hiring', 'E-commerce'] },
  { id: 'design', name: 'Art & design', hue: 320, subs: ['Drawing', 'Illustration', 'Graphic design', 'UI/UX', 'Inspiration'] },
  { id: 'coding', name: 'Coding', hue: 226, subs: ['Web dev', 'Mobile', 'Backend', 'DevOps', 'Algorithms'] }
];

const PLATFORMS = [
  { id: 'x', name: 'X', icon: '𝕏' },
  { id: 'instagram', name: 'Instagram', icon: '📷' },
  { id: 'youtube', name: 'YouTube', icon: '▶' },
  { id: 'tiktok', name: 'TikTok', icon: '🎵' },
  { id: 'web', name: 'Web', icon: '🌐' }
];

// Demo bookmark titles by category
const DEMO_TITLES = {
  ai: [
    'The Future of AI Agents',
    'GPT-4 Prompting Techniques',
    'Building Chatbots with LangChain',
    'Midjourney Tips for Beginners',
    'Local LLM Setup Guide',
    'AI Code Review Tools Comparison',
    'Prompt Engineering Masterclass',
    'Stable Diffusion Tutorial',
    'AI Ethics and Safety',
    'Fine-tuning vs RAG Explained'
  ],
  fitness: [
    '30-Min HIIT Workout',
    'How to Start Running',
    'Yoga for Lower Back Pain',
    'Progressive Overload Explained',
    'Best Foam Rolling Techniques',
    'Morning Mobility Routine',
    'Strength Training for Beginners',
    'Marathon Training Plan',
    'Recovery Tips for Athletes',
    'Home Workout Equipment Guide'
  ],
  recipes: [
    'Easy Weeknight Pasta',
    'Meal Prep for the Week',
    'Chocolate Chip Cookie Recipe',
    'Quick Breakfast Ideas',
    'Vegetarian Chili Recipe',
    'Air Fryer Chicken Wings',
    'Sourdough Starter Guide',
    'Sheet Pan Dinner Ideas',
    'Protein-Packed Smoothies',
    'One-Pot Curry Recipe'
  ],
  tech: [
    'iPhone 15 Pro Review',
    'Best Wireless Earbuds 2026',
    'M3 MacBook Air Impressions',
    'Smart Home Setup Guide',
    'Gaming Laptop Recommendations',
    'Monitor Buying Guide',
    'Mechanical Keyboard Guide',
    'Ergonomic Desk Setup',
    'Cable Management Tips',
    'Tech Deals This Week'
  ],
  travel: [
    'Tokyo Travel Guide',
    'Budget Backpacking Europe',
    '48 Hours in NYC',
    'Best Hotels in Bali',
    'Packing Light Tips',
    'Travel Photography Guide',
    'Flight Booking Strategies',
    'Solo Travel Safety',
    'Hidden Gems in Italy',
    'Weekend Getaway Ideas'
  ],
  business: [
    'Y Combinator Application Tips',
    'Product-Market Fit Guide',
    'Startup Fundraising 101',
    'Building a Remote Team',
    'SaaS Pricing Strategies',
    'Customer Retention Tactics',
    'Business Plan Template',
    'Marketing on a Budget',
    'Hiring Your First Employee',
    'Startup Metrics That Matter'
  ],
  design: [
    'Color Theory Basics',
    'Figma to Production Workflow',
    'Typography Best Practices',
    'UI Animation Principles',
    'Portfolio Website Examples',
    'Design System Guide',
    'Icon Design Tutorial',
    'Procreate Illustration',
    'Layout Composition Tips',
    'Dark Mode Design Patterns'
  ],
  coding: [
    'React Best Practices',
    'Node.js Performance Tips',
    'Python for Data Science',
    'Git Workflow Guide',
    'API Design Principles',
    'Database Schema Design',
    'Docker for Beginners',
    'Testing Strategies',
    'Code Review Checklist',
    'Debugging Techniques'
  ]
};

// ========================================
// Scene Setup
// ========================================

let scene, camera, renderer, controls;
let rooms = [];
let bookmarkObjects = [];
let raycaster, mouse;
let hoveredObject = null;
let isOnTour = false;
let tourStep = 0;
let demoData = [];

function init() {
  // Scene
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0xF6F3EE);
  scene.fog = new THREE.Fog(0xF6F3EE, 80, 200);

  // Detect dark mode
  if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    scene.background = new THREE.Color(0x14110E);
    scene.fog = new THREE.Fog(0x14110E, 80, 200);
  }

  // Camera
  camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 500);
  camera.position.set(0, 40, 80);
  camera.lookAt(0, 0, 0);

  // Renderer
  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  document.getElementById('canvas-container').appendChild(renderer.domElement);

  // Controls
  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.05;
  controls.minDistance = 20;
  controls.maxDistance = 150;
  controls.maxPolarAngle = Math.PI / 2.1;

  // Raycaster
  raycaster = new THREE.Raycaster();
  mouse = new THREE.Vector2();

  // Lights
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
  scene.add(ambientLight);

  const mainLight = new THREE.DirectionalLight(0xffffff, 0.8);
  mainLight.position.set(50, 80, 40);
  mainLight.castShadow = true;
  mainLight.shadow.camera.left = -100;
  mainLight.shadow.camera.right = 100;
  mainLight.shadow.camera.top = 100;
  mainLight.shadow.camera.bottom = -100;
  mainLight.shadow.mapSize.width = 2048;
  mainLight.shadow.mapSize.height = 2048;
  scene.add(mainLight);

  const fillLight = new THREE.DirectionalLight(0xFFE9E1, 0.3);
  fillLight.position.set(-40, 30, -30);
  scene.add(fillLight);

  // Ground
  const groundGeometry = new THREE.PlaneGeometry(300, 300);
  const groundMaterial = new THREE.MeshStandardMaterial({ 
    color: 0xEAE4DA,
    roughness: 0.9,
    metalness: 0.0
  });
  const ground = new THREE.Mesh(groundGeometry, groundMaterial);
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  // Generate demo data
  generateDemoData();

  // Build palace
  buildPalace();

  // Event listeners
  window.addEventListener('resize', onWindowResize);
  window.addEventListener('mousemove', onMouseMove);
  window.addEventListener('click', onClick);

  // UI event listeners
  document.getElementById('tour-btn').addEventListener('click', startTour);
  document.getElementById('map-btn').addEventListener('click', goToMapView);
  document.getElementById('reset-btn').addEventListener('click', resetCamera);
  document.getElementById('close-info').addEventListener('click', hideInfoPanel);

  // Hide loading
  document.getElementById('loading').style.display = 'none';

  // Show welcome info
  showInfoPanel({
    title: 'Memory Palace',
    subtitle: `${demoData.length} bookmarks across ${TAXONOMY.length} categories`,
    desc: 'Navigate through themed rooms where each category is a wing and bookmarks float as glowing orbs. Click a room to explore, or start the guided tour.'
  });

  // Start animation loop
  animate();
}

// ========================================
// Data Generation
// ========================================

function generateDemoData() {
  demoData = [];
  let id = 1;

  TAXONOMY.forEach(category => {
    const titles = DEMO_TITLES[category.id] || [];
    const numBookmarks = Math.floor(Math.random() * 6) + 15; // 15-20 per category

    for (let i = 0; i < numBookmarks; i++) {
      const platform = PLATFORMS[Math.floor(Math.random() * PLATFORMS.length)];
      const sub = category.subs[Math.floor(Math.random() * category.subs.length)];
      const title = titles[i % titles.length] || `${category.name} Bookmark ${i + 1}`;

      demoData.push({
        id: id++,
        title,
        category: category.id,
        categoryName: category.name,
        subcategory: sub,
        platform: platform.id,
        platformName: platform.name,
        platformIcon: platform.icon,
        hue: category.hue
      });
    }
  });
}

// ========================================
// Palace Construction
// ========================================

function buildPalace() {
  const radius = 50; // Distance from center
  const angleStep = (Math.PI * 2) / TAXONOMY.length;

  TAXONOMY.forEach((category, index) => {
    const angle = angleStep * index;
    const x = Math.cos(angle) * radius;
    const z = Math.sin(angle) * radius;

    const room = createRoom(category, x, z, angle);
    rooms.push(room);
    scene.add(room.group);

    // Add bookmarks to this room
    const categoryBookmarks = demoData.filter(b => b.category === category.id);
    addBookmarksToRoom(room, categoryBookmarks);
  });

  // Central structure
  createCentralHub();
}

function createRoom(category, x, z, angle) {
  const group = new THREE.Group();
  group.position.set(x, 0, z);

  // Room color from category hue
  const color = new THREE.Color().setHSL(category.hue / 360, 0.6, 0.5);
  const lightColor = new THREE.Color().setHSL(category.hue / 360, 0.4, 0.7);

  // Floor platform
  const platformGeometry = new THREE.CylinderGeometry(12, 12, 1, 32);
  const platformMaterial = new THREE.MeshStandardMaterial({ 
    color: lightColor,
    roughness: 0.7,
    metalness: 0.1
  });
  const platform = new THREE.Mesh(platformGeometry, platformMaterial);
  platform.position.y = 0.5;
  platform.castShadow = true;
  platform.receiveShadow = true;
  group.add(platform);

  // Walls (partial circle facing center)
  const wallHeight = 15;
  const wallGeometry = new THREE.CylinderGeometry(11.5, 11.5, wallHeight, 32, 1, true, Math.PI * 0.7, Math.PI * 1.6);
  const wallMaterial = new THREE.MeshStandardMaterial({ 
    color: color,
    side: THREE.DoubleSide,
    roughness: 0.8,
    metalness: 0.0
  });
  const wall = new THREE.Mesh(wallGeometry, wallMaterial);
  wall.position.y = wallHeight / 2;
  wall.castShadow = true;
  wall.receiveShadow = true;
  group.add(wall);

  // Roof
  const roofGeometry = new THREE.ConeGeometry(13, 6, 32);
  const roofMaterial = new THREE.MeshStandardMaterial({ 
    color: color,
    roughness: 0.6,
    metalness: 0.1
  });
  const roof = new THREE.Mesh(roofGeometry, roofMaterial);
  roof.position.y = wallHeight + 3;
  roof.castShadow = true;
  group.add(roof);

  // Category label (3D text simulation with sprite)
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = 128;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 72px "Bricolage Grotesque", sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(category.name, 256, 64);

  const texture = new THREE.CanvasTexture(canvas);
  const spriteMaterial = new THREE.SpriteMaterial({ map: texture });
  const sprite = new THREE.Sprite(spriteMaterial);
  sprite.position.y = wallHeight + 8;
  sprite.scale.set(16, 4, 1);
  group.add(sprite);

  // Accent light
  const accentLight = new THREE.PointLight(color, 1, 30);
  accentLight.position.y = 10;
  group.add(accentLight);

  return {
    group,
    category,
    position: { x, z },
    color,
    bookmarks: []
  };
}

function createCentralHub() {
  // Central pillar
  const pillarGeometry = new THREE.CylinderGeometry(3, 4, 20, 16);
  const pillarMaterial = new THREE.MeshStandardMaterial({ 
    color: 0xFF5A2D,
    roughness: 0.5,
    metalness: 0.2
  });
  const pillar = new THREE.Mesh(pillarGeometry, pillarMaterial);
  pillar.position.y = 10;
  pillar.castShadow = true;
  pillar.receiveShadow = true;
  scene.add(pillar);

  // Top ornament
  const orbGeometry = new THREE.SphereGeometry(2, 32, 32);
  const orbMaterial = new THREE.MeshStandardMaterial({ 
    color: 0xFF5A2D,
    emissive: 0xFF5A2D,
    emissiveIntensity: 0.3,
    roughness: 0.3,
    metalness: 0.5
  });
  const orb = new THREE.Mesh(orbGeometry, orbMaterial);
  orb.position.y = 22;
  scene.add(orb);

  // Central light
  const centerLight = new THREE.PointLight(0xFF5A2D, 1.5, 50);
  centerLight.position.y = 22;
  scene.add(centerLight);
}

function addBookmarksToRoom(room, bookmarks) {
  const roomGroup = room.group;

  bookmarks.forEach((bookmark, index) => {
    const angle = (index / bookmarks.length) * Math.PI * 2;
    const radius = 5 + Math.random() * 4;
    const height = 3 + Math.random() * 10;

    const x = Math.cos(angle) * radius;
    const z = Math.sin(angle) * radius;

    const bookmarkObj = createBookmarkObject(bookmark);
    bookmarkObj.position.set(x, height, z);
    bookmarkObj.userData = bookmark;

    roomGroup.add(bookmarkObj);
    bookmarkObjects.push(bookmarkObj);
    room.bookmarks.push(bookmarkObj);
  });
}

function createBookmarkObject(bookmark) {
  const group = new THREE.Group();

  // Icon/card base
  const hue = bookmark.hue / 360;
  const color = new THREE.Color().setHSL(hue, 0.7, 0.6);

  const geometry = new THREE.BoxGeometry(1.5, 2, 0.3);
  const material = new THREE.MeshStandardMaterial({ 
    color: color,
    emissive: color,
    emissiveIntensity: 0.2,
    roughness: 0.4,
    metalness: 0.3
  });
  const card = new THREE.Mesh(geometry, material);
  group.add(card);

  // Glow
  const glowGeometry = new THREE.SphereGeometry(0.5, 16, 16);
  const glowMaterial = new THREE.MeshBasicMaterial({ 
    color: color,
    transparent: true,
    opacity: 0.3
  });
  const glow = new THREE.Mesh(glowGeometry, glowMaterial);
  group.add(glow);

  // Floating animation offset
  group.userData.floatOffset = Math.random() * Math.PI * 2;
  group.userData.floatSpeed = 0.5 + Math.random() * 0.5;

  return group;
}

// ========================================
// Animation & Interaction
// ========================================

function animate() {
  requestAnimationFrame(animate);

  const time = Date.now() * 0.001;

  // Animate bookmarks (floating)
  bookmarkObjects.forEach(obj => {
    const offset = obj.userData.floatOffset || 0;
    const speed = obj.userData.floatSpeed || 1;
    obj.position.y += Math.sin(time * speed + offset) * 0.01;
    obj.rotation.y += 0.005;
  });

  // Animate central orb
  const orbs = scene.children.filter(c => c.geometry && c.geometry.type === 'SphereGeometry');
  orbs.forEach(orb => {
    if (orb.position.y > 20) {
      orb.rotation.y += 0.01;
    }
  });

  // Tour animation
  if (isOnTour) {
    updateTour();
  }

  controls.update();
  renderer.render(scene, camera);
}

function onWindowResize() {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
}

function onMouseMove(event) {
  mouse.x = (event.clientX / window.innerWidth) * 2 - 1;
  mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;

  raycaster.setFromCamera(mouse, camera);
  const intersects = raycaster.intersectObjects(bookmarkObjects, true);

  const tooltip = document.getElementById('tooltip');

  if (intersects.length > 0) {
    const obj = intersects[0].object.parent || intersects[0].object;
    
    if (hoveredObject !== obj) {
      if (hoveredObject) resetObjectScale(hoveredObject);
      hoveredObject = obj;
      highlightObject(obj);
    }

    const bookmark = obj.userData;
    if (bookmark && bookmark.title) {
      tooltip.textContent = `${bookmark.platformIcon} ${bookmark.title}`;
      tooltip.style.left = `${event.clientX + 15}px`;
      tooltip.style.top = `${event.clientY + 15}px`;
      tooltip.classList.add('visible');
    }
  } else {
    if (hoveredObject) {
      resetObjectScale(hoveredObject);
      hoveredObject = null;
    }
    tooltip.classList.remove('visible');
  }

  document.body.style.cursor = intersects.length > 0 ? 'pointer' : 'default';
}

function onClick(event) {
  raycaster.setFromCamera(mouse, camera);
  const intersects = raycaster.intersectObjects(bookmarkObjects, true);

  if (intersects.length > 0) {
    const obj = intersects[0].object.parent || intersects[0].object;
    const bookmark = obj.userData;
    
    if (bookmark && bookmark.title) {
      showInfoPanel({
        title: bookmark.title,
        subtitle: `${bookmark.platformIcon} ${bookmark.platformName} · ${bookmark.categoryName}`,
        desc: `Subcategory: ${bookmark.subcategory}\n\nIn a real implementation, clicking would open the original link.`
      });
    }
  }
}

function highlightObject(obj) {
  obj.scale.set(1.3, 1.3, 1.3);
}

function resetObjectScale(obj) {
  obj.scale.set(1, 1, 1);
}

// ========================================
// Camera Controls
// ========================================

function goToMapView() {
  isOnTour = false;
  animateCamera(
    new THREE.Vector3(0, 100, 0.1),
    new THREE.Vector3(0, 0, 0),
    1500
  );
}

function resetCamera() {
  isOnTour = false;
  animateCamera(
    new THREE.Vector3(0, 40, 80),
    new THREE.Vector3(0, 0, 0),
    1500
  );
}

function animateCamera(targetPosition, targetLookAt, duration) {
  const startPosition = camera.position.clone();
  const startLookAt = controls.target.clone();
  const startTime = Date.now();

  function update() {
    const elapsed = Date.now() - startTime;
    const progress = Math.min(elapsed / duration, 1);
    const eased = easeInOutCubic(progress);

    camera.position.lerpVectors(startPosition, targetPosition, eased);
    controls.target.lerpVectors(startLookAt, targetLookAt, eased);
    controls.update();

    if (progress < 1) {
      requestAnimationFrame(update);
    }
  }

  update();
}

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

// ========================================
// Guided Tour
// ========================================

function startTour() {
  if (isOnTour) {
    isOnTour = false;
    tourStep = 0;
    document.getElementById('tour-btn').innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10"/>
        <polygon points="10 8 16 12 10 16 10 8"/>
      </svg>
      Guided Tour
    `;
    return;
  }

  isOnTour = true;
  tourStep = 0;
  document.getElementById('tour-btn').innerHTML = `
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <rect x="6" y="4" width="4" height="16"/>
      <rect x="14" y="4" width="4" height="16"/>
    </svg>
    Stop Tour
  `;

  // Start with overview
  showInfoPanel({
    title: 'Welcome to the Memory Palace',
    subtitle: 'Starting guided tour',
    desc: 'Each room represents a category. We\'ll fly through each one, showing how your bookmarks are organized in 3D space.'
  });

  goToMapView();
  setTimeout(() => visitNextRoom(), 2000);
}

function visitNextRoom() {
  if (!isOnTour || tourStep >= rooms.length) {
    if (isOnTour) {
      isOnTour = false;
      document.getElementById('tour-btn').innerHTML = `
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"/>
          <polygon points="10 8 16 12 10 16 10 8"/>
        </svg>
        Guided Tour
      `;
      showInfoPanel({
        title: 'Tour Complete',
        subtitle: 'Memory Palace',
        desc: 'Explore on your own by clicking rooms or bookmarks, or start the tour again!'
      });
    }
    return;
  }

  const room = rooms[tourStep];
  const targetPos = new THREE.Vector3(
    room.position.x * 0.3,
    25,
    room.position.z * 0.3 + 30
  );
  const lookAt = new THREE.Vector3(room.position.x, 8, room.position.z);

  animateCamera(targetPos, lookAt, 2000);

  showInfoPanel({
    title: room.category.name,
    subtitle: `${room.bookmarks.length} bookmarks`,
    desc: `Subtopics: ${room.category.subs.slice(0, 3).join(', ')}, and more...`
  });

  tourStep++;
  setTimeout(() => visitNextRoom(), 4000);
}

function updateTour() {
  // Tour is handled by timeouts in visitNextRoom
}

// ========================================
// UI Helpers
// ========================================

function showInfoPanel(data) {
  const panel = document.getElementById('info-panel');
  document.getElementById('info-title').textContent = data.title;
  document.getElementById('info-subtitle').innerHTML = data.subtitle;
  document.getElementById('info-desc').textContent = data.desc;
  panel.classList.add('visible');
}

function hideInfoPanel() {
  document.getElementById('info-panel').classList.remove('visible');
}

// ========================================
// Start
// ========================================

init();
