/// A vehicle insurance policy extracted from a shared photo/PDF of the
/// policy document -- see chat_global_image's POLICY section on the
/// backend and POST /vehicle-policies (ConversationService.saveVehiclePolicy).
class VehiclePolicy {
  final int? id;
  // User-facing short name ("Bike", "Activa") -- what file_vehicle_insurance_claim
  // matches against when the user says "file a claim for my bike".
  final String? label;
  final String insurerName;
  final String policyNumber;
  final String? vehicleRegistration;
  final String? insuredName;
  final String? issueDate;
  final String? expiryDate;
  final double? sumInsured;
  // Sometimes printed on the document and pre-filled when found, but
  // always shown editable in the confirm sheet -- never auto-extracted-
  // and-trusted, since a wrong address is a silently undeliverable claim
  // later, not just a cosmetic mistake.
  final String? claimsEmail;
  // 'comprehensive' | 'own_damage' | 'third_party' -- Indian motor
  // insurance routinely splits own-damage and third-party liability
  // across two different insurers with different policy numbers, so a
  // vehicle can have up to two VehiclePolicy rows at once. Defaults to
  // 'comprehensive' when the document doesn't make the split explicit.
  final String coverageType;

  const VehiclePolicy({
    this.id,
    this.label,
    required this.insurerName,
    required this.policyNumber,
    this.vehicleRegistration,
    this.insuredName,
    this.issueDate,
    this.expiryDate,
    this.sumInsured,
    this.claimsEmail,
    this.coverageType = 'comprehensive',
  });

  /// From chat_global_image's response `policy` object -- backend-read
  /// values, before the user has had a chance to edit them in the confirm
  /// sheet. No `id` yet (not saved). claims_email/coverage_type are
  /// extraction guesses, pre-filled but always left editable.
  factory VehiclePolicy.fromExtraction(Map<String, dynamic> json) => VehiclePolicy(
        insurerName: json['insurer_name'] as String,
        policyNumber: json['policy_number'] as String,
        vehicleRegistration: json['vehicle_registration'] as String?,
        insuredName: json['insured_name'] as String?,
        issueDate: json['issue_date'] as String?,
        expiryDate: json['expiry_date'] as String?,
        sumInsured: (json['sum_insured'] as num?)?.toDouble(),
        claimsEmail: json['claims_email'] as String?,
        coverageType: json['coverage_type'] as String? ?? 'comprehensive',
      );

  VehiclePolicy copyWith({
    String? label,
    String? insurerName,
    String? policyNumber,
    String? vehicleRegistration,
    String? insuredName,
    String? issueDate,
    String? expiryDate,
    double? sumInsured,
    String? claimsEmail,
    String? coverageType,
  }) =>
      VehiclePolicy(
        id: id,
        label: label ?? this.label,
        insurerName: insurerName ?? this.insurerName,
        policyNumber: policyNumber ?? this.policyNumber,
        vehicleRegistration: vehicleRegistration ?? this.vehicleRegistration,
        insuredName: insuredName ?? this.insuredName,
        issueDate: issueDate ?? this.issueDate,
        expiryDate: expiryDate ?? this.expiryDate,
        sumInsured: sumInsured ?? this.sumInsured,
        claimsEmail: claimsEmail ?? this.claimsEmail,
        coverageType: coverageType ?? this.coverageType,
      );
}
