class Catalog {
  Catalog.fromJson(Map<String, dynamic> json)
    : requireCustomerName =
          (json['settings'] as Map?)?['require_customer_name'] == true,
      products = List.unmodifiable(
        (json['products'] as List? ?? []).map(
          (v) => CatalogProduct.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
  final List<CatalogProduct> products;
  final bool requireCustomerName;
}

class CatalogProduct {
  CatalogProduct.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      price = json['price'] as int,
      available = json['is_available'] == true,
      variants = List.unmodifiable(
        (json['variants'] as List? ?? []).map(
          (v) => CatalogVariant.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      addons = List.unmodifiable(
        (json['addons'] as List? ?? []).map(
          (v) => CatalogAddon.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
  final String id, name;
  final int price;
  final bool available;
  final List<CatalogVariant> variants;
  final List<CatalogAddon> addons;
}

class CatalogVariant {
  CatalogVariant.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      groupName = json['group_name'] as String,
      priceModifier = json['price_modifier'] as int,
      available = json['is_available'] == true;
  final String id, name, groupName;
  final int priceModifier;
  final bool available;
}

class CatalogAddon {
  CatalogAddon.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      price = json['price'] as int,
      available = json['is_available'] == true;
  final String id, name;
  final int price;
  final bool available;
}
