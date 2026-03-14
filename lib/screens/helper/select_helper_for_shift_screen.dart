import 'package:flutter/material.dart';
import 'helper_marketplace_screen.dart';

class SelectHelperForShiftScreen extends StatelessWidget {
  const SelectHelperForShiftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HelperMarketplaceScreen(
      onHelperSelected: (helper) {
        Navigator.pop(context, helper);
      },
    );
  }
}