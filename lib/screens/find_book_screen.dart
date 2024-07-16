import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

class BookSearchScreen extends StatefulWidget {
  final void Function(String, int) openBookCallback;
  final void Function() closeLeftPaneCallback;
  final FocusNode focusNode;
  final String libraryRootPath;

  const BookSearchScreen(
      {Key? key,
      required this.openBookCallback,
      required this.closeLeftPaneCallback,
      required this.focusNode,
      required this.libraryRootPath})
      : super(key: key);

  @override
  BookSearchScreenState createState() => BookSearchScreenState();
}

class BookSearchScreenState extends State<BookSearchScreen> {
  TextEditingController searchController = TextEditingController();

  late final List<String> books;

  @override
  initState() {
    super.initState();
    books =
        Directory('${widget.libraryRootPath}${Platform.pathSeparator}אוצריא')
            .listSync(recursive: true)
            .whereType<File>()
            .map((e) => e.path)
            .toList();

    searchController.addListener(() => _searchBooks(searchController.text));
  }

  List<String> _searchResults = [];

  void _searchBooks(String query) async {
    final results = books.where((book) {
      final bookName = book.split(Platform.pathSeparator).last;
      // if all the words seperated by spaces exist in the book name, even not in order, return true
      bool result = true;
      for (final word in query.split(' ')) {
        result = result && bookName.contains(word);
      }
      return result;
    }).toList();
    //sort the results by their levenstien distance
    if (query.isNotEmpty) {
      results.sort(
        (a, b) => ratio(query, b.split(Platform.pathSeparator).last.trim())
            .compareTo(
                ratio(query, a.split(Platform.pathSeparator).last.trim())),
      );
    }
    // sort alphabetic
    else {
      results.sort((a, b) => a
          .split(Platform.pathSeparator)
          .last
          .trim()
          .compareTo(b.split(Platform.pathSeparator).last.trim()));
    }

    setState(() {
      _searchResults = results;
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('חיפוש ספר'),
        ),
        body: Center(
          child: Column(
            children: [
              TextField(
                focusNode: widget.focusNode,
                autofocus: true,
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'הקלד שם ספר: ',
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final book = _searchResults[index];
                    return ListTile(
                        title: Text(book.split(Platform.pathSeparator).last),
                        onTap: () {
                          //close the sidebar
                          widget.closeLeftPaneCallback();
                          Future.microtask(() {
                            //open the book
                            widget.openBookCallback(book, 0);
                            //clear textField
                            searchController.clear();
                          });
                        });
                  },
                ),
              ),
            ],
          ),
        ));
  }
}
