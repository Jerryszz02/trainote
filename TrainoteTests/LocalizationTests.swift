import Foundation
import XCTest
@testable import Trainote

@MainActor
final class LocalizationTests: XCTestCase {
  private func languageRestoration() -> () -> Void {
    let preference = LanguageSettings.shared.preference
    let preferredLanguages = LanguageSettings.shared.preferredLanguages
    let regionalLocale = LanguageSettings.shared.regionalLocale
    return {
      LanguageSettings.shared.preference = preference
      LanguageSettings.shared.refreshSystem(preferredLanguages: preferredLanguages,
        regionalLocale: regionalLocale)
    }
  }

  func testLanguagePreferencePersistsAndInvalidValueUsesSystem() throws {
    let suite = "Trainote.LocalizationTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = LanguageSettings(defaults: defaults, preferredLanguages: ["en-GB"])
    XCTAssertEqual(settings.preference, .system)
    XCTAssertEqual(settings.language, .english)
    for preference in [AppLanguage.simplifiedChinese, .english, .system] {
      settings.preference = preference
      XCTAssertEqual(defaults.string(forKey: LanguageSettings.preferenceKey), preference.rawValue)
      XCTAssertEqual(LanguageSettings(defaults: defaults, preferredLanguages: ["en-GB"]).preference,
        preference)
    }
    defaults.set("obsolete-language", forKey: LanguageSettings.preferenceKey)
    XCTAssertEqual(LanguageSettings(defaults: defaults, preferredLanguages: ["zh-Hans"]).preference,
      .system)
  }

  func testSystemResolutionSupportsEnglishAndSimplifiedChineseWithoutMatchingTraditional() {
    for identifier in ["en", "en-GB", "en_US"] {
      XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: [identifier]), .english)
    }
    for identifier in ["zh", "zh-Hans", "zh-CN", "zh_Hans_CN", "zh-SG"] {
      XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: [identifier]), .simplifiedChinese)
    }
    for identifier in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh_Hant_TW"] {
      XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: [identifier]), .english)
    }
    XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: ["fr-FR", "ja-JP"]), .english)
    XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: []), .english)
    XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: ["zh-Hant", "zh-Hans"]),
      .simplifiedChinese)
    XCTAssertEqual(AppLanguage.resolve(.english, preferredLanguages: ["zh-Hans"]), .english)
    XCTAssertEqual(AppLanguage.resolve(.simplifiedChinese, preferredLanguages: ["en"]), .simplifiedChinese)
  }

  func testReturningToSystemRefreshesLanguageAndPreservesRegionalDecimalConvention() throws {
    let suite = "Trainote.LocalizationTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = LanguageSettings(defaults: defaults, preferredLanguages: ["en-GB"],
      regionalLocale: Locale(identifier: "en_DE"))
    settings.preference = .simplifiedChinese
    XCTAssertEqual(settings.language, .simplifiedChinese)
    XCTAssertEqual(settings.locale.decimalSeparator, ",")
    settings.refreshSystem(preferredLanguages: ["en-GB"], regionalLocale: Locale(identifier: "en_DE"))
    XCTAssertEqual(settings.language, .simplifiedChinese)
    settings.preference = .system
    XCTAssertEqual(settings.language, .english)
    XCTAssertEqual(settings.locale.decimalSeparator, ",")
    settings.refreshSystem(preferredLanguages: ["zh-Hans"], regionalLocale: Locale(identifier: "zh_CN"))
    XCTAssertEqual(settings.language, .simplifiedChinese)
    XCTAssertEqual(settings.locale.decimalSeparator, ".")
  }

  func testShippedCatalogLookupPluralOutputAndMissingKeyFallback() throws {
    let restore = languageRestoration()
    defer { restore() }
    XCTAssertNotNil(Bundle.main.path(forResource: "en", ofType: "lproj"))
    XCTAssertNotNil(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    LanguageSettings.shared.refreshSystem(preferredLanguages: ["en-GB"],
      regionalLocale: Locale(identifier: "en_GB"))
    LanguageSettings.shared.preference = .english
    XCTAssertEqual(L10n.text("language.system"), "System Default")
    XCTAssertEqual(L10n.text("core.reps", 1), "1 rep")
    XCTAssertEqual(L10n.text("core.reps", 2), "2 reps")
    XCTAssertEqual(L10n.text("core.sets", 0), "0 sets")
    XCTAssertEqual(L10n.text("missing.localization.test.key"), "missing.localization.test.key")
    let openMessage = L10n.Message("language.system")
    LanguageSettings.shared.preference = .simplifiedChinese
    XCTAssertEqual(L10n.text("language.system"), "跟随系统")
    XCTAssertEqual(openMessage.text, "跟随系统")
    XCTAssertEqual(L10n.text("core.reps", 1), "1 次")
    XCTAssertEqual(L10n.text("core.reps", 2), "2 次")
    XCTAssertEqual(L10n.render("language.system", arguments: [], language: .english), "System Default")
  }

  func testDecimalDraftUsesCapturedRegionAndRejectsPartialGarbage() {
    let comma = Locale(identifier: "en_DE")
    let point = Locale(identifier: "en_GB")
    XCTAssertEqual(DecimalInput.parse("62,5", locale: comma), 62.5)
    XCTAssertEqual(DecimalInput.parse("62,", locale: comma), 62)
    XCTAssertEqual(DecimalInput.parse("62.5", locale: point), 62.5)
    XCTAssertEqual(DecimalInput.parse("62.", locale: point), 62)
    for text in ["", ",", "1,2,3", "62.5", "62kg", "NaN", "1 234,5"] {
      XCTAssertNil(DecimalInput.parse(text, locale: comma), text)
    }
    XCTAssertNil(DecimalInput.parse("62,5", locale: point))
    let restore = languageRestoration()
    defer { restore() }
    LanguageSettings.shared.refreshSystem(preferredLanguages: ["en"], regionalLocale: comma)
    for language in [AppLanguage.english, .simplifiedChinese] {
      LanguageSettings.shared.preference = language
      XCTAssertEqual(NutritionFormatting.number(62.5), "62,5")
    }
  }

  private func item(nameEn: String = "Dumbbell press", nameZh: String = "哑铃推举") -> ExerciseCatalogItem {
    .init(id: "localization-test-exercise", nameEn: nameEn, nameZh: nameZh,
      bodyPart: "chest", equipment: "dumbbell", target: "pectorals", muscleGroup: "chest",
      secondaryMuscles: ["triceps"], instructionsEn: "Press slowly.", instructionsZh: "缓慢推起。",
      stepsEn: ["Hold the dumbbells."], stepsZh: ["握住哑铃。"])
  }

  func testExerciseSearchMatchesBothNamesAndTranslatedFiltersInEitherLanguage() {
    let restore = languageRestoration()
    defer { restore() }
    let exercise = item()
    let catalog = ExerciseCatalog(items: [exercise])
    for language in [AppLanguage.english, .simplifiedChinese] {
      LanguageSettings.shared.preference = language
      for query in ["DUMBBELL PRESS", "哑铃推举", "哑铃", "胸部", "triceps"] {
        XCTAssertEqual(catalog.filtered(query: query).map(\.id), [exercise.id], "\(language): \(query)")
      }
      XCTAssertEqual(catalog.filtered(query: "", equipment: "dumbbell").map(\.id), [exercise.id])
      XCTAssertTrue(catalog.filtered(query: "", bodyPart: "back").isEmpty)
    }
    LanguageSettings.shared.preference = .english
    XCTAssertEqual(exercise.displayName, "Dumbbell press")
    XCTAssertEqual(exercise.displayInstructions, "Press slowly.")
    XCTAssertEqual(exercise.displaySteps, ["Hold the dumbbells."])
    LanguageSettings.shared.preference = .simplifiedChinese
    XCTAssertEqual(exercise.displayName, "哑铃推举")
    XCTAssertEqual(exercise.displayInstructions, "缓慢推起。")
    XCTAssertEqual(exercise.displaySteps, ["握住哑铃。"])
    XCTAssertEqual(item(nameEn: "", nameZh: "保留中文").displayName, "保留中文")
    LanguageSettings.shared.preference = .english
    XCTAssertEqual(item(nameEn: "", nameZh: "保留中文").displayName, "保留中文")
  }

  func testFactoriesStoreOriginalBilingualSnapshotsWhileDisplayNamesSwitch() {
    let restore = languageRestoration()
    defer { restore() }
    let exercise = item()
    LanguageSettings.shared.preference = .english
    let activeExercise = RoutineFactory.workoutExercise(from: exercise, orderIndex: 2)
    let routineExercise = RoutineFactory.routineExercise(from: exercise, orderIndex: 2)
    let routine = Routine(name: "我的训练模板", notes: "用户笔记", exercises: [routineExercise])
    let workout = RoutineFactory.workout(from: routine)
    let copied = workout.exercises[0]
    for value in [activeExercise, copied] {
      XCTAssertEqual(value.sourceExerciseID, exercise.id)
      XCTAssertEqual(value.nameZhSnapshot, exercise.nameZh)
      XCTAssertEqual(value.nameEnSnapshot, exercise.nameEn)
      XCTAssertEqual(value.displayName, exercise.nameEn)
    }
    XCTAssertEqual(routineExercise.nameZhSnapshot, exercise.nameZh)
    XCTAssertEqual(routineExercise.nameEnSnapshot, exercise.nameEn)
    XCTAssertEqual(routineExercise.displayName, exercise.nameEn)
    XCTAssertEqual(workout.title, routine.name)
    XCTAssertEqual(workout.routineNameSnapshot, routine.name)
    LanguageSettings.shared.preference = .simplifiedChinese
    XCTAssertEqual(activeExercise.displayName, exercise.nameZh)
    XCTAssertEqual(copied.displayName, exercise.nameZh)
    XCTAssertEqual(routineExercise.displayName, exercise.nameZh)
    XCTAssertEqual(activeExercise.nameZhSnapshot, exercise.nameZh)
    XCTAssertEqual(copied.nameEnSnapshot, exercise.nameEn)
    XCTAssertEqual(routine.name, "我的训练模板")
    XCTAssertEqual(routine.notes, "用户笔记")
    XCTAssertEqual(workout.title, "我的训练模板")
  }
}
