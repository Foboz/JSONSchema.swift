import Foundation

protocol Validator {
  typealias Validation = (Validator, Any, Any, [String: Any]) -> (ValidationResult)

  var schema: [String: Any] { get }
  var validations: [String: Validation] { get }
  var formats: [String: (String) -> (ValidationResult)] { get }
}

extension Validator {
  func validate(instance: Any) -> ValidationResult {
    return validate(instance: instance, schema: schema)
  }

  func validate(instance: Any, schema: Any) -> ValidationResult {
    if let schema = schema as? Bool {
      if schema == true {
        return .valid
      }

      return .invalid(["Falsy schema"])
    }

    guard let schema = schema as? [String: Any] else {
      return .valid
    }

    if let ref = schema["$ref"] as? String {
      let validation = validations["$ref"]!
      return validation(self, ref, instance, schema)
    }

    var results = [ValidationResult]()
    for (key, validation) in validations {
      if let value = schema[key] {
        results.append(validation(self, value, instance, schema))
      }
    }

    return flatten(results)
  }

  func resolve(ref: String) -> (Any) -> (ValidationResult) {
    return validatorForReference(ref)
  }

  func validatorForReference(_ reference: String) -> (Any) -> (ValidationResult) {
    // TODO: Rewrite this whole block: https://github.com/kylef/JSONSchema.swift/issues/12

    if reference == "http://json-schema.org/draft-04/schema#" {
      return { Draft4Validator(schema: DRAFT_04_META_SCHEMA).descend(instance: $0, subschema: DRAFT_04_META_SCHEMA) }
    }

    if let reference = reference.stringByRemovingPrefix("#") {  // Document relative
      if let tmp = reference.stringByRemovingPrefix("/"), let reference = (tmp as NSString).removingPercentEncoding {
        var components = reference.components(separatedBy: "/")
        var schema = self.schema
        while let component = components.first {
          components.remove(at: components.startIndex)

          if let subschema = schema[component] as? [String:Any] {
            schema = subschema
            continue
          } else if let schemas = schema[component] as? [[String:Any]] {
            if let component = components.first, let index = Int(component) {
              components.remove(at: components.startIndex)

              if schemas.count > index {
                schema = schemas[index]
                continue
              }
            }
          }

          return invalidValidation("Reference not found '\(component)' in '\(reference)'")
        }

        return { self.descend(instance: $0, subschema: schema) }
      } else if reference == "" {
        return { self.descend(instance: $0, subschema: self.schema) }
      }
    }

    return invalidValidation("Remote $ref '\(reference)' is not yet supported")
  }

  func descend(instance: Any, subschema: Any) -> ValidationResult {
    return validate(instance: instance, schema: subschema)
  }
}
