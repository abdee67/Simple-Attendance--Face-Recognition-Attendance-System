import 'dart:math';

class NotificationTexts {
  final List<String> _morningMessages = [
    "🌅 RISE AND SHINE! Your morning consistency sets the tone for an extraordinary day ahead!",
    "☀️ MORNING WIN! Showing up early is already putting you ahead of 99% of people today!",
    "🚀 DAY STARTER! This morning check-in is launching you toward massive success today!",
    "💪 MORNING POWER! You've already won the first battle by showing up. Now conquer the day!",
    "⭐ EARLY EXCELLENCE! The most successful people master their mornings. That's you!",
    "🔥 MORNING FIRE! Your dedication while others sleep is building your future empire!",
    "🎯 FIRST TARGET HIT! Morning consistency = daily victory. You're already winning!",
    "🌈 SUNRISE SUCCESS! Today's opportunities meet your preparation. Make it count!",
    "⚡ ENERGY BOOST! Your morning discipline generates power for the entire day!",
    "🏆 CHAMPION START! Champions don't wait for motivation—they create it like you just did!",
    "🌄 DAWN OF GREATNESS! This morning effort is writing your success story!",
    "✨ MORNING MAGIC! You're not just starting a day—you're building a legacy!",
    "📈 MORNING MOMENTUM! Small morning wins create massive day-long success!",
    "🦁 ROAR INTO THE DAY! Your morning strength signals dominance all day long!",
    "🎪 DAY MAKER! You've already done what most won't. Now own this day completely!",
  ];
  final List<String> _lunchMessages = [
    "🍽️ MIDDAY POWER-UP! Refuel your body and refocus your mind for an epic second half!",
    "⚡ HALFTIME BOOST! You've conquered the morning—now recharge for an even better afternoon!",
    "🎯 NOON TARGET! Perfect timing! This break is strategic refueling for maximum productivity!",
    "💪 LUNCHTIME RECHARGE! Great first half! Now fuel up for an even more powerful finish!",
    "🌞 MIDDAY CHECKPOINT! You're halfway to victory. Refuel and accelerate!",
    "🔥 AFTERBURNER ENGAGE! Lunch isn't a break—it's strategic fueling for afternoon domination!",
    "🏆 HALFTIME CHAMPION! You've earned this break. Now prepare for the winning second half!",
    "🚀 AFTERNOON LAUNCHPAD! This meal is rocket fuel for your post-lunch productivity!",
    "🌈 NOON RECHARGE! The best is yet to come. Fuel up for an spectacular afternoon!",
    "⭐ LUNCHTIME EXCELLENCE! Even your breaks are strategic. That's next-level thinking!",
    "📈 PRODUCTIVITY BOOST! Smart pause = smarter performance. You're doing it right!",
    "🎪 MIDDAY CIRCUS! You're juggling tasks like a pro. Time to refuel the performer!",
    "🧠 MENTAL REFUEL! Your brain deserves this break. Come back sharper and stronger!",
    "⚓ ANCHOR MOMENT! This lunch break stabilizes your day for steady afternoon progress!",
    "🎖️ EARNED BREAK! You've fought hard this morning. Now regroup for afternoon victory!",
  ];
  final List<String> _eveningMessages = [
    "🌙 DAY COMPLETE! Your consistency today built tomorrow's success. Be proud!",
    "🏁 FINISH STRONG! You've shown up all day. This final check-in seals your victory!",
    "🎯 TARGET ACHIEVED! Perfect day complete! Your consistency is becoming your superpower!",
    "⭐ DAY PERFECT! You navigated today's challenges with excellence. Tomorrow awaits!",
    "🔥 UNSTOPPABLE DAY! From morning fire to evening glow—you dominated today!",
    "📊 SUCCESS LOGGED! Another day of excellence recorded. Your future self thanks you!",
    "🌈 SUNSET SUCCESS! As the day ends, your achievements shine bright. Well done!",
    "💎 DAILY DIAMOND! You've polished another day into a gem of productivity!",
    "🚀 MISSION ACCOMPLISHED! Today's consistency launched tomorrow's opportunities!",
    "🎖️ DAILY MEDAL EARNED! You competed against yesterday's self and won!",
    "⚡ ENERGY WELL-SPENT! You invested your day wisely. Returns are coming!",
    "🧠 MIND AT PEACE! You gave today your all. Now rest and recharge for tomorrow!",
    "🏆 CHAMPION'S REST! You fought well today. Earned recovery starts now!",
    "✨ DAY WELL-LIVED! Your consistency today built confidence for tomorrow!",
    "🌅 TOMORROW'S FOUNDATION! Today's effort built tomorrow's success. Sleep well!",
  ];
  String getContexualMessage() {
    final now = DateTime.now();
    if (now.hour < 12) {
      return _morningMessages[Random().nextInt(_morningMessages.length)];
    } else if (now.hour < 17) {
      return _lunchMessages[Random().nextInt(_lunchMessages.length)];
    } else {
      return _eveningMessages[Random().nextInt(_eveningMessages.length)];
    }
  }
}
