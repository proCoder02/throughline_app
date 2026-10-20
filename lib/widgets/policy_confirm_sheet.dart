import 'package:flutter/material.dart';

import '../models/vehicle_policy.dart';
import '../theme.dart';

/// Shown right after a policy-document share produces a VehiclePolicy (see
/// GlobalChatBody's post-_sendImage hook) -- lets the user fix a misread
/// field, and always asks for the claims email (almost never printed on
/// the document itself) before it's saved via
/// ConversationService.saveVehiclePolicy. Same showModalBottomSheet pattern
/// as showTransactionConfirmSheet. Returns the (possibly edited)
/// VehiclePolicy on Save, or null on Discard.
Future<VehiclePolicy?> showPolicyConfirmSheet(BuildContext context, VehiclePolicy policy) {
  final labelController = TextEditingController(text: policy.label ?? '');
  final insurerController = TextEditingController(text: policy.insurerName);
  final policyNumberController = TextEditingController(text: policy.policyNumber);
  final vehicleRegController = TextEditingController(text: policy.vehicleRegistration ?? '');
  final issueDateController = TextEditingController(text: policy.issueDate ?? '');
  final expiryDateController = TextEditingController(text: policy.expiryDate ?? '');
  final sumInsuredController = TextEditingController(text: policy.sumInsured?.toStringAsFixed(0) ?? '');
  final claimsEmailController = TextEditingController(text: policy.claimsEmail ?? '');
  var coverageType = policy.coverageType;

  const coverageLabels = {
    'comprehensive': 'Comprehensive',
    'own_damage': 'Own Damage',
    'third_party': 'Third Party',
  };

  InputDecoration deco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.dmBubbleIn,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );

  return showModalBottomSheet<VehiclePolicy>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: AppColors.dmAccent, size: 20),
                      const SizedBox(width: 8),
                      Text('Save this policy?', style: appHeadlineFont(color: AppColors.dmText, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Check the details, and add the insurer\'s claims email -- it\'s rarely on the document itself.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft),
                  ),
                  const SizedBox(height: 16),
                  // A vehicle can legitimately have a SEPARATE own-damage and
                  // third-party policy (often different insurers) -- this says
                  // which one THIS document is, so file_vehicle_insurance_claim
                  // can route a claim to the right insurer later.
                  SegmentedButton<String>(
                    segments: coverageLabels.entries
                        .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                        .toList(),
                    selected: {coverageType},
                    onSelectionChanged: (selection) => setSheetState(() => coverageType = selection.first),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: labelController, autofocus: true, decoration: deco('Label (optional)', hint: 'e.g. Bike, Activa')),
                  const SizedBox(height: 10),
                  TextField(controller: insurerController, decoration: deco('Insurer')),
                  const SizedBox(height: 10),
                  TextField(controller: policyNumberController, decoration: deco('Policy number')),
                  const SizedBox(height: 10),
                  TextField(controller: vehicleRegController, decoration: deco('Vehicle registration (optional)')),
                  const SizedBox(height: 10),
                  TextField(controller: issueDateController, decoration: deco('Issue date (optional)', hint: 'YYYY-MM-DD')),
                  const SizedBox(height: 10),
                  TextField(controller: expiryDateController, decoration: deco('Expiry date (optional)', hint: 'YYYY-MM-DD')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sumInsuredController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: deco('Sum insured (optional)', hint: 'Insured declared value'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: claimsEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: deco('Claims email', hint: 'e.g. claims@insurer.com'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Discard'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final insurer = insurerController.text.trim();
                            final policyNumber = policyNumberController.text.trim();
                            final claimsEmail = claimsEmailController.text.trim();
                            if (insurer.isEmpty || policyNumber.isEmpty || claimsEmail.isEmpty) return;
                            final sumInsured = double.tryParse(sumInsuredController.text.trim());
                            Navigator.of(sheetContext).pop(VehiclePolicy(
                              label: labelController.text.trim().isEmpty ? null : labelController.text.trim(),
                              insurerName: insurer,
                              policyNumber: policyNumber,
                              vehicleRegistration: vehicleRegController.text.trim().isEmpty ? null : vehicleRegController.text.trim(),
                              issueDate: issueDateController.text.trim().isEmpty ? null : issueDateController.text.trim(),
                              expiryDate: expiryDateController.text.trim().isEmpty ? null : expiryDateController.text.trim(),
                              sumInsured: sumInsured,
                              claimsEmail: claimsEmail,
                              coverageType: coverageType,
                            ));
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
