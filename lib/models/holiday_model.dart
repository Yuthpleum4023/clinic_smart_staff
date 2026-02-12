class Holiday {
  final String date; // yyyy-MM-dd
  final String name; // เช่น "วันสงกรานต์"

  Holiday({
    required this.date,
    required this.name,
  });

  Map<String, dynamic> toMap() => {
        'date': date,
        'name': name,
      };

  factory Holiday.fromMap(Map<String, dynamic> map) {
    final d = map['date'];
    final n = map['name'];

    return Holiday(
      date: (d == null) ? '' : d.toString(),
      name: (n == null) ? '' : n.toString(),
    );
  }

  bool get isValid => date.isNotEmpty;
}
