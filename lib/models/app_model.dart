/*this class represents the state of the application.
it includes the library, a list of the opened tabs, the current tab, the current view, 
and the some other app settings like dark mode and the seed color*/

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:hive/hive.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/data/data.dart';
import 'package:otzaria/data/file_system_data_provider.dart';
import 'package:otzaria/models/bookmark.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/library.dart';
import 'package:otzaria/models/tabs.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

/// Represents the state of the application.
///
/// It includes the library, a list of the opened tabs, the current tab,
/// the current view, and the some other app settings like dark mode and
/// the seed color.
class AppModel with ChangeNotifier {
  /// The data provider for the application.
  Data data = FileSystemData.instance;

  /// The library of books.
  late Library library;

  /// The list of opened tabs.
  List<OpenedTab> tabs = [];

  /// The index of the current tab.
  int currentTab = 0;

  /// The index of the current view.
  ValueNotifier<Screens> currentView = ValueNotifier(Screens.library);

  late List<Bookmark> bookmarks;

  late List<Bookmark> history;

  /// Flag indicating if the app is in dark mode.
  final ValueNotifier<bool> isDarkMode = ValueNotifier<bool>(
    Settings.getValue<bool>('key-dark-mode') ?? false,
  );

  /// The color used as seed.
  final ValueNotifier<Color> seedColor = ValueNotifier<Color>(
    ConversionUtils.colorFromString(
        Settings.getValue<String>('key-swatch-color') ?? ('#ff2c1b02')),
  );

  /// The color used as seed.
  final ValueNotifier<double> paddingSize = ValueNotifier<double>(
      Settings.getValue<double>('key-padding-size') ?? 10);

  // if you should show only otzar hachochma books
  final ValueNotifier<bool> showOnlyOtzarHachochma = ValueNotifier<bool>(
    Settings.getValue<bool>('key-show-only-otzar-hachochma') ?? false,
  );

  /// a focus node for the search field in libraryBrowser
  FocusNode bookLocatorFocusNode = FocusNode();

  /// Constructs a new AppModel instance.
  ///
  /// This constructor initializes the library and tabs list, and loads the
  /// tabs list and history from disk.
  AppModel() {
    library = data.getLibrary();

//load tabs from disk. if fails, delete the tabs from disk
    try {
      tabs = List<OpenedTab>.from(
          ((Hive.box(name: 'tabs').get('key-tabs', defaultValue: [])) as List)
              .map((e) => OpenedTab.fromJson(e))
              .toList());
    } catch (e) {
      print('error loading tabs from disk: $e');
      Hive.box(name: 'tabs').put('key-tabs', []);
    }

    ///load the current tab from disk
    currentTab = Hive.box(name: 'tabs').get('key-current-tab', defaultValue: 0);

    //if there are any tabs, set the current view to reading
    if (tabs.isNotEmpty) {
      currentView.value = Screens.reading;
    }

    //load bookmarks
    try {
      final List<dynamic> rawBookmarks =
          Hive.box(name: 'bookmarks').get('key-bookmarks') ?? [];
      bookmarks = rawBookmarks.map((e) => Bookmark.fromJson(e)).toList();
    } catch (e) {
      bookmarks = [];
      print('error loading bookmarks from disk: $e');
      Hive.box(name: 'bookmarks').put('key-bookmarks', []);
    }

    //load history
    try {
      final List<dynamic> rawHistory =
          Hive.box(name: 'history').get('key-history') ?? [];
      history = rawHistory.map((e) => Bookmark.fromJson(e)).toList();
    } catch (e) {
      history = [];
      print('error loading history from disk: $e');
      Hive.box(name: 'history').put('key-history', []);
    }

    seedColor.addListener(() {
      notifyListeners();
    });
    isDarkMode.addListener(() {
      notifyListeners();
    });
    showOnlyOtzarHachochma.addListener(() {
      Settings.setValue(
          'key-show-only-otzar-hachochma', showOnlyOtzarHachochma.value);
      notifyListeners();
    });
  }

  /// Opens a book in a new tab.
  ///
  /// [book] The book to open.
  /// [index] The index of the book.
  void openBook(Book book, int index, {bool openLeftPane = false}) {
    if (book is PdfBook) {
      _addTab(PdfBookTab(book, max(index, 1)));
    } else if (book is TextBook) {
      _addTab(
          TextBookTab(book: book, index: index, openLeftPane: openLeftPane));
    }
    //show the reading screen
    currentView.value = Screens.reading;
  }

  /// Opens a new search tab.
  ///
  /// This function creates a new `SearchingTab` instance with the title "חיפוש"
  /// and adds it to the list of opened tabs.
  ///
  /// Does not return anything.
  void openNewSearchTab() {
    _addTab(SearchingTab('חיפוש'));
  }

  /// Adds a new tab to the list of opened tabs.
  ///
  /// [tab] The tab to add.
  void _addTab(OpenedTab tab) {
    //add the tab after the current tab, or at the end if this is the last tab
    tabs.insert(min(currentTab + 1, tabs.length), tab);
    //opdate the current tab, while making sure it is not goes beyond the list.
    currentTab = min(currentTab + 1, tabs.length - 1);
    notifyListeners();
    saveTabsToDisk();
  }

  void openTab(OpenedTab tab, {int index = 1}) {
    if (tab is PdfBookTab) {
      openBook(tab.book, index);
      return;
    } else {
      _addTab(tab);
      currentView.value = Screens.reading;
    }
  }

  /// Closes a tab.
  ///
  /// [tab] The tab to close.
  void closeTab(OpenedTab tab) {
    addTabToHistory(tab);
    tabs.remove(tab);
    currentTab = max(currentTab - 1, 0);
    notifyListeners();
    saveTabsToDisk();
  }

  void addTabToHistory(OpenedTab tab) {
    if (tab is PdfBookTab) {
      int index = tab.pdfViewerController.isReady
          ? tab.pdfViewerController.pageNumber!
          : 1;
      addHistory(
        ref: '${tab.title} עמוד $index',
        book: tab.book,
        index: index,
      );
    }
    if (tab is TextBookTab) {
      final index = tab.positionsListener.itemPositions.value.isEmpty
          ? 0
          : tab.positionsListener.itemPositions.value.first.index;
      (() async => addHistory(
          ref: await utils.refFromIndex(index, tab.tableOfContents),
          book: tab.book,
          index: index))();
    }
  }

  void closeCurrentTab() {
    closeTab(tabs[currentTab]);
  }

  void goToPreviousTab() {
    if (currentTab > 0) {
      currentTab--;
      notifyListeners();
    }
  }

  void goToNextTab() {
    if (currentTab < tabs.length - 1) {
      currentTab++;
      notifyListeners();
    }
  }

  /// Closes all tabs.
  void closeAllTabs() {
    for (final tab in tabs) {
      addTabToHistory(tab);
    }
    tabs = [];
    currentTab = 0;
    notifyListeners();
    saveTabsToDisk();
  }

  void closeOthers(OpenedTab tab) {
    for (int i = 0; i < tabs.length; i++) {
      if (tabs[i] != tab) {
        addTabToHistory(tabs[i]);
      }
    }
    tabs = [tab];
    currentTab = 0;
    notifyListeners();
    saveTabsToDisk();
  }

  void cloneTab(OpenedTab tab) {
    _addTab(OpenedTab.from(tab));
  }

  void moveTab(OpenedTab tab, int newIndex) {
    tabs.remove(tab);
    tabs.insert(
      newIndex,
      tab,
    );
    notifyListeners();
  }

  /// Saves the list of tabs and  the current tab index to disk.
  void saveTabsToDisk() {
    Hive.box(name: 'tabs').put("key-tabs", tabs);
    Hive.box(name: 'tabs').put("key-current-tab", currentTab);
  }

  void addBookmark(
      {required String ref, required Book book, required int index}) {
    bookmarks.add(Bookmark(ref: ref, book: book, index: index));
    // write to disk
    Hive.box(name: 'bookmarks').put('key-bookmarks', bookmarks);
  }

  void removeBookmark(int index) {
    bookmarks.removeAt(index);
    Hive.box(name: 'bookmarks').put('key-bookmarks', bookmarks);
  }

  void clearBookmarks() {
    bookmarks.clear();
    Hive.box(name: 'bookmarks').clear();
  }

  void addHistory(
      {required String ref, required Book book, required int index}) {
    if (book is TextBook) {
      history.insert(0, Bookmark(ref: ref, book: book, index: index));
    }
    // write to disk
    Hive.box(name: 'history').put('key-history', history);
  }

  void removeHistory(int index) {
    history.removeAt(index);
    Hive.box(name: 'history').put('key-history', history);
  }

  void clearHistory() {
    history.clear();
    Hive.box(name: 'history').clear();
  }

  String getDafYomi(DateTime date) {
    JewishCalendar jewishCalendar = JewishCalendar.fromDateTime(date);
    Daf dafYomi = YomiCalculator.getDafYomiBavli(jewishCalendar);
    int dafNumber = dafYomi.getDaf();
    String masechtaNameHebrew = dafYomi.getMasechta();
    Object dafNumberHebrew =
        HebrewDateFormatter().formatHebrewNumber(dafNumber);
    return '$masechtaNameHebrew $dafNumberHebrew';
  }

  String getHebrewDateFormattedAsString(DateTime dateTime) {
    final hebrewCalendar = JewishCalendar.fromDateTime(dateTime);
    HebrewDateFormatter hebrewDateFormatter = HebrewDateFormatter()
      ..hebrewFormat = true;
    return hebrewDateFormatter.format(hebrewCalendar);
  }
}

/// An enum that represents the different screens in the application.
enum Screens { library, reading, search, favorites, settings }
