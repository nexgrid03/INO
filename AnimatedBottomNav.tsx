/**
 * AnimatedBottomNav — a pill-shaped bottom bar with a center FAB that fans out
 * a three-item quick-action menu in a shallow arc.
 *
 * Stack: React Native + Expo, expo-router, react-native-reanimated v3 (worklets),
 * react-native-safe-area-context, @expo/vector-icons.
 *
 * Mount ONCE at the root of your screen/layout (e.g. inside app/_layout.tsx,
 * as the last child so it overlays page content). The whole component is an
 * absolutely-positioned, `box-none` overlay: it never pushes or reflows page
 * content — the scrim and options are absolute layers above the bar.
 *
 * To add/remove a quick action, edit ACTIONS in ONE place (and, because a
 * Reanimated shared value + animated style are created per action, the arrays
 * below map over ACTIONS so they scale with it automatically).
 */

import { Ionicons } from '@expo/vector-icons';
import { usePathname, useRouter } from 'expo-router';
import React, { useEffect, useRef, useState } from 'react';
import {
  AppState,
  BackHandler,
  Pressable,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
} from 'react-native';
import Animated, {
  Easing,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withDelay,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

// ---------------------------------------------------------------------------
// Design tokens
// ---------------------------------------------------------------------------

const TEAL = '#14A38B';
const LABEL_COLOR = '#0F6E56';
const SCRIM_COLOR = 'rgba(230,244,241,0.72)';
const RIPPLE_COLOR = 'rgba(20,163,139,0.14)';
const INACTIVE = '#94A3B8';

const BAR_HEIGHT = 62;
const FAB_SIZE = 56;
const FAB_RAISE = 22; // FAB overlaps the bar's top edge by this much
const OPTION_SIZE = 54;
const OPTION_BOX = 76; // circle + label column width

// Motion
const SPRING = { damping: 14, stiffness: 180, mass: 0.9 } as const;
const CLOSE_TIMING = { duration: 220, easing: Easing.out(Easing.cubic) } as const;
const SCRIM_TIMING = { duration: 300, easing: Easing.out(Easing.cubic) } as const;
const RIPPLE_TIMING = { duration: 600, easing: Easing.out(Easing.cubic) } as const;
const REDUCED_TIMING = { duration: 150, easing: Easing.linear } as const;

// ---------------------------------------------------------------------------
// Quick-action config — the single source of truth. Add/remove here.
// tx/ty are the OPEN-state translation of the option's centre, relative to the
// FAB centre. openDelay/closeDelay drive the stagger (close reverses the order).
// ---------------------------------------------------------------------------

type Action = {
  key: string;
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  route: string;
  tx: number;
  ty: number;
  openDelay: number;
  closeDelay: number;
};

const ACTIONS: Action[] = [
  {
    key: 'expenses',
    label: 'Expenses',
    icon: 'wallet-outline',
    route: '/expenses/new',
    tx: -78,
    ty: -64,
    openDelay: 20,
    closeDelay: 120, // closes last
  },
  {
    key: 'scan',
    label: 'Scan',
    icon: 'scan-outline',
    route: '/scan',
    tx: 0,
    ty: -104,
    openDelay: 70,
    closeDelay: 70,
  },
  {
    key: 'notes',
    label: 'Notes',
    icon: 'pencil-outline',
    route: '/notes/new',
    tx: 78,
    ty: -64,
    openDelay: 120,
    closeDelay: 20, // closes first (reverse order)
  },
];

// The four resting tabs (the centre slot is the FAB).
const TABS = [
  { key: 'home', icon: 'home-outline' as const, active: 'home' as const, route: '/home' },
  { key: 'wallet', icon: 'wallet-outline' as const, active: 'wallet' as const, route: '/wallet' },
  { key: 'notifications', icon: 'notifications-outline' as const, active: 'notifications' as const, route: '/notifications' },
  { key: 'profile', icon: 'person-outline' as const, active: 'person' as const, route: '/profile' },
];

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function AnimatedBottomNav() {
  const router = useRouter();
  const pathname = usePathname();
  const insets = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const reduced = useReducedMotion();

  // The ONE boolean that owns the menu. Both the FAB rotation and every option
  // are derived from this, so a rapid double-tap can never desync them.
  const [open, setOpen] = useState(false);

  // ---- Geometry ----------------------------------------------------------
  const bottomInset = insets.bottom + 14;
  const fabCenterX = width / 2;
  const fabCenterFromBottom = bottomInset + BAR_HEIGHT / 2 + FAB_RAISE;
  const fabCenterFromTop = height - fabCenterFromBottom;

  // ---- Reanimated drivers ------------------------------------------------
  // One shared value per action (stable-length map — ACTIONS is a module const).
  /* eslint-disable react-hooks/rules-of-hooks */
  const progress = ACTIONS.map(() => useSharedValue(0));
  const optionStyles = ACTIONS.map((a, i) =>
    useAnimatedStyle(() => {
      const p = progress[i].value;
      return {
        opacity: p,
        transform: [
          { translateX: a.tx * p },
          { translateY: a.ty * p },
          { scale: 0.2 + 0.8 * p },
        ],
      };
    }),
  );
  /* eslint-enable react-hooks/rules-of-hooks */

  const fab = useSharedValue(0); // 0 → 1 (rotation 0° → 135°)
  const scrim = useSharedValue(0);
  const ripple = useSharedValue(0);

  const fabStyle = useAnimatedStyle(() => ({
    transform: [{ rotate: `${fab.value * 135}deg` }],
  }));
  const scrimStyle = useAnimatedStyle(() => ({ opacity: scrim.value }));
  const rippleStyle = useAnimatedStyle(() => ({
    opacity: (1 - ripple.value) * 0.9,
    transform: [{ scale: 1 + ripple.value * 1.1 }],
  }));

  // ---- Drive the animation from `open` -----------------------------------
  useEffect(() => {
    ACTIONS.forEach((a, i) => {
      if (open) {
        progress[i].value = reduced
          ? withTiming(1, REDUCED_TIMING)
          : withDelay(a.openDelay, withSpring(1, SPRING)); // slight overshoot
      } else {
        progress[i].value = reduced
          ? withTiming(0, REDUCED_TIMING)
          : withDelay(a.closeDelay, withTiming(0, CLOSE_TIMING)); // no overshoot
      }
    });

    if (reduced) {
      fab.value = withTiming(open ? 1 : 0, REDUCED_TIMING);
      scrim.value = withTiming(open ? 1 : 0, REDUCED_TIMING);
    } else {
      fab.value = open ? withSpring(1, SPRING) : withTiming(0, CLOSE_TIMING);
      scrim.value = withTiming(open ? 1 : 0, SCRIM_TIMING);
      if (open) {
        // Restart the ripple ring on each open (skip entirely if reduced).
        ripple.value = 0;
        ripple.value = withTiming(1, RIPPLE_TIMING);
      }
    }
    // progress/fab/scrim/ripple are stable shared-value refs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, reduced]);

  // ---- Edge cases --------------------------------------------------------

  // Android hardware back closes the menu instead of navigating back.
  useEffect(() => {
    if (!open) return;
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      setOpen(false);
      return true; // consume
    });
    return () => sub.remove();
  }, [open]);

  // Auto-close when the app leaves the foreground.
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state !== 'active') setOpen(false);
    });
    return () => sub.remove();
  }, []);

  // Auto-close on route change.
  const lastPath = useRef(pathname);
  useEffect(() => {
    if (lastPath.current !== pathname) {
      lastPath.current = pathname;
      setOpen(false);
    }
  }, [pathname]);

  // ---- Handlers ----------------------------------------------------------
  const toggle = () => setOpen((o) => !o);

  const onSelect = (route: string) => {
    setOpen(false);
    router.push(route as never);
  };

  const isActive = (route: string) =>
    pathname === route || pathname.startsWith(`${route}/`);

  // ---- Render ------------------------------------------------------------
  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="box-none">
      {/* Scrim — full screen, taps close the menu. Below the options & FAB. */}
      <Animated.View
        style={[styles.scrim, scrimStyle]}
        pointerEvents={open ? 'auto' : 'none'}
      >
        <Pressable
          style={StyleSheet.absoluteFill}
          onPress={() => setOpen(false)}
          accessibilityRole="button"
          accessibilityLabel="Close quick actions"
        />
      </Animated.View>

      {/* Ripple ring — behind the FAB. */}
      <Animated.View
        pointerEvents="none"
        style={[
          styles.ripple,
          {
            left: fabCenterX - FAB_SIZE / 2,
            top: fabCenterFromTop - FAB_SIZE / 2,
          },
          rippleStyle,
        ]}
      />

      {/* Quick-action options — absolute overlay, no reflow. */}
      {ACTIONS.map((a, i) => (
        <Animated.View
          key={a.key}
          pointerEvents={open ? 'auto' : 'none'}
          style={[
            styles.option,
            {
              left: fabCenterX - OPTION_BOX / 2,
              top: fabCenterFromTop - OPTION_SIZE / 2,
            },
            optionStyles[i],
          ]}
        >
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={a.label}
            onPress={() => onSelect(a.route)}
            style={styles.optionPress}
          >
            <View style={styles.optionCircle}>
              <Ionicons name={a.icon} size={22} color={TEAL} />
            </View>
            <Text style={styles.optionLabel} numberOfLines={1}>
              {a.label}
            </Text>
          </Pressable>
        </Animated.View>
      ))}

      {/* The bar itself. */}
      <View
        style={[styles.bar, { bottom: bottomInset }]}
        pointerEvents="box-none"
      >
        {TABS.slice(0, 2).map((t) => (
          <TabButton
            key={t.key}
            icon={isActive(t.route) ? t.active : t.icon}
            active={isActive(t.route)}
            onPress={() => router.push(t.route as never)}
          />
        ))}

        {/* Centre gap reserved for the FAB. */}
        <View style={{ width: FAB_SIZE }} />

        {TABS.slice(2).map((t) => (
          <TabButton
            key={t.key}
            icon={isActive(t.route) ? t.active : t.icon}
            active={isActive(t.route)}
            onPress={() => router.push(t.route as never)}
          />
        ))}
      </View>

      {/* FAB — separate absolute layer so it can overlap the bar's top edge
          without Android clipping. Rendered last → sits above the options,
          which fan out from behind it. */}
      <Animated.View
        pointerEvents="box-none"
        style={[
          styles.fabWrap,
          {
            left: fabCenterX - FAB_SIZE / 2,
            bottom: fabCenterFromBottom - FAB_SIZE / 2,
          },
        ]}
      >
        <Pressable
          onPress={toggle}
          accessibilityRole="button"
          accessibilityState={{ expanded: open }}
          accessibilityLabel={open ? 'Close quick actions' : 'Open quick actions'}
          style={styles.fab}
        >
          <Animated.View style={fabStyle}>
            <Ionicons name="add" size={26} color="#FFFFFF" />
          </Animated.View>
        </Pressable>
      </Animated.View>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Resting tab button
// ---------------------------------------------------------------------------

function TabButton({
  icon,
  active,
  onPress,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable style={styles.tab} onPress={onPress} accessibilityRole="button">
      <Ionicons name={icon} size={24} color={active ? TEAL : INACTIVE} />
    </Pressable>
  );
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  scrim: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: SCRIM_COLOR,
  },
  bar: {
    position: 'absolute',
    left: 12,
    right: 12,
    height: BAR_HEIGHT,
    borderRadius: 999,
    backgroundColor: '#FFFFFF',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    paddingHorizontal: 8,
    // Soft floating shadow.
    shadowColor: '#0F172A',
    shadowOpacity: 0.1,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 8 },
    elevation: 12,
  },
  tab: {
    flex: 1,
    height: BAR_HEIGHT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  fabWrap: {
    position: 'absolute',
    width: FAB_SIZE,
    height: FAB_SIZE,
  },
  fab: {
    width: FAB_SIZE,
    height: FAB_SIZE,
    borderRadius: FAB_SIZE / 2,
    backgroundColor: TEAL,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: TEAL,
    shadowOpacity: 0.4,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 8,
  },
  ripple: {
    position: 'absolute',
    width: FAB_SIZE,
    height: FAB_SIZE,
    borderRadius: FAB_SIZE / 2,
    backgroundColor: RIPPLE_COLOR,
  },
  option: {
    position: 'absolute',
    width: OPTION_BOX,
    alignItems: 'center',
  },
  optionPress: {
    alignItems: 'center',
  },
  optionCircle: {
    width: OPTION_SIZE,
    height: OPTION_SIZE,
    borderRadius: OPTION_SIZE / 2,
    backgroundColor: '#FFFFFF',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#0F172A',
    shadowOpacity: 0.12,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 6,
  },
  optionLabel: {
    marginTop: 6,
    fontSize: 11,
    fontWeight: '500',
    color: LABEL_COLOR,
    textAlign: 'center',
  },
});
