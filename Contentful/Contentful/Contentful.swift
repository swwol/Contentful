//
//  Contentful.swift
//  DeviceManagement
//
//  Created by Sam Woolf on 17/10/2017.
//  Copyright © 2017 Nice Agency. All rights reserved.
//

import Foundation

private typealias StringDict = [String:String?]
private typealias IntDict = [String:Int?]
private typealias DoubleDict = [String:Double?]
private typealias BoolDict = [String:Bool?]
private typealias OneRefDict = [String: [String:StringDict]?]
private typealias ManyRefDict = [String:  [[String:StringDict]]? ]

public struct PageRequest {
    
    public static func prepareRequest(forContent contentType: String, fromSpace spaceId: String,  page: Page) -> (endpoint: String, query: [URLQueryItem]) {
        let endpoint = "/spaces/\(spaceId)/entries"
        
        let contentQuery =  URLQueryItem(name: "content_type", value: contentType)
        let selectQuery = URLQueryItem(name: "select", value: "sys.id,sys.version,fields")
        let limitQuery = URLQueryItem(name: "limit", value: "\(page.itemsPerPage)")
        let skipQuery = URLQueryItem(name: "skip", value: "\(page.itemsPerPage * page.currentPage)")
        let queries = [contentQuery, selectQuery, limitQuery,skipQuery]
        
        return (endpoint, queries)
    }
}

public struct SingleEntryRequest {
    public static func prepareRequest(forEntryId entryId: String, fromSpace spaceId: String) -> String {
        return "/spaces/\(spaceId)/entries/\(entryId)"
    }
}

public struct PageUnboxing {
    
    public static func unboxResponse<T>(data: Data, locale: Locale?, with fieldUnboxer: @escaping (() -> (FieldMapping)), via creator: @escaping ((UnboxedFields) -> T)) -> Result<PagedResult<T>>  {
        let decoder = JSONDecoder()
        
        decoder.userInfo = [CodingUserInfoKey(rawValue: "fieldUnboxer")!: fieldUnboxer, CodingUserInfoKey(rawValue: "creator")!: creator]
        
        if let locale = locale {
            decoder.userInfo.updateValue(locale, forKey: CodingUserInfoKey(rawValue: "locale")!)
        }
        
        do {
            let response = try decoder.decode(Response<T>.self, from: data)
            let entries = response.entries
            let failures = response.failures
            let page = Page(itemsPerPage: response.limit, currentPage: response.skip/response.limit, totalItemsAvailable: response.total)
            return .success(PagedResult(validItems: entries, failedItems: failures, page: page))
        } catch {
            return .error(error as! Swift.DecodingError)
        }
    }
}

public struct ObjectEncoding {
    
    public static func encode<T: Encodable>(object: T, locale: LocaleCode) -> (data: Data, sysData: SysData)? {
        
        let encoder = JSONEncoder()
        
        guard let jsonData = try? encoder.encode(object),
            let jsonObject = try? JSONSerialization.jsonObject(with: jsonData,options: []),
            let jsonDict = jsonObject as? [String: Any] else { return nil }
        
        let sysData = SysData(id: object.contentful_id, version: object.contentful_version)
        
        var contentfulFieldsDict: [String:Any] = [:]
        
        for key in jsonDict.keys {
            
            if key != "contentful_id" && key != "contentful_version" {
                let nestedDict = [locale.rawValue: jsonDict[key] ?? ""]
                contentfulFieldsDict.updateValue(nestedDict, forKey: key)
            }
        }
        
        let contentfulDict: [String: Any] = ["fields": contentfulFieldsDict]
        
        if let data = try? JSONSerialization.data(withJSONObject: contentfulDict, options: []) {
            return (data: data, sysData: sysData)
        }
        
        return nil
    }
}

public struct Publishing {
    
    public static func preparePublishRequest<T: Writeable> (forEntry entry: T, toSpace spaceId: String ) -> (endpoint:String, headers:  [(String,String)])  {
        let endpoint =   "/spaces/\(spaceId)/entries/\(entry.contentful_id)/published"
        let headers = [("X-Contentful-Version","\(entry.contentful_version)")]
        return (endpoint: endpoint, headers: headers)
    }
    
    public static func preparePublishRequest (forEntryID entryID: String, entryVersion version: String,  toSpace spaceId: String ) -> (endpoint:String, headers:  [(String,String)]) {
        let endpoint =  "/spaces/\(spaceId)/entries/\(entryID)/published"
        let headers = [("X-Contentful-Version","\(version)")]
        return (endpoint: endpoint, headers: headers)
    }
}

public struct Creating {
    
    public static func prepareCreateEntryRequest<T: Readable & Encodable > ( forEntry entry: T, localeCode: LocaleCode, toSpace spaceId: String) -> WriteRequest?  {
        let endpoint = "/spaces/\(spaceId)/entries"
        let headers = [("X-Contentful-Content-Type","\(T.contentfulEntryType())")]
        guard let data = ObjectEncoding.encode(object: entry, locale: localeCode) else { return nil }
        
        return (data: data.data, endpoint: endpoint, headers: headers, method: .post)
    }
}

public struct Writing {
    
    public static func prepareWriteRequest<T: Encodable> (forEntry entry: T, localeCode: LocaleCode, toSpace spaceId: String ) -> WriteRequest? {
        let endpoint = "/spaces/\(spaceId)/entries/\(entry.contentful_id)"
        let headers =  [("X-Contentful-Version","\(entry.contentful_version)"),("Content-Type","application/vnd.contentful.management.v1+json") ]
        
        guard let data = ObjectEncoding.encode(object: entry, locale: localeCode) else { return nil }
        
        return (data: data.data, endpoint: endpoint, headers: headers, method: .put)
    }
}

public struct ItemUnboxing {
    
    public static func unbox <T>(data: Data, locale: Locale?, with fieldUnboxer: @escaping (() -> (FieldMapping)), via creator: @escaping ((UnboxedFields) -> T)) -> Result<ItemResult<T>> {
        let decoder = JSONDecoder()
        
        decoder.userInfo = [CodingUserInfoKey(rawValue: "fieldUnboxer")!: fieldUnboxer, CodingUserInfoKey(rawValue: "creator")!: creator]
        
        if let locale = locale {
            decoder.userInfo.updateValue(locale, forKey: CodingUserInfoKey(rawValue: "locale")!)
        }
        
        do {
            let unboxed  = try decoder.decode(Unboxable<T>.self, from: data)
            return Result.success(unboxed.item)
            
        } catch {
            return Result.error(error as! Swift.DecodingError)
        }
    }
}

//MARK: JSON decoding keys

private struct Response<T> : Swift.Decodable {
    
    let total: Int
    let skip: Int
    let limit: Int
    
    let entries: [T]
    let failures: [(Int, DecodingError)]
    
    enum CodingKeys: String, CodingKey {
        case total
        case skip
        case limit
        case entries = "items"
    }
    
    init (from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decode(Int.self, forKey: .total)
        skip = try container.decode(Int.self, forKey: .skip)
        limit = try container.decode(Int.self, forKey: .limit)
        
        let unboxables: [Unboxable<T>] = try container.decode([Unboxable<T>].self, forKey: .entries)
        
        var entries: [T] = []
        var failures: [(Int, DecodingError)] = []
        
        for i in 0..<unboxables.count {
            switch unboxables[i].item {
            case .success(let entry):
                entries.append(entry)
            case .error(let error):
                failures.append( (i,error))
            }
        }
        
        self.entries = entries
        self.failures = failures
    }
}

private enum EntryCodingKeys: String, CodingKey {
    case sys
    case fields
}

private enum EntrySysCodingKeys: String, CodingKey {
    case id 
    case version
}

private struct GenericCodingKeys: CodingKey {
    var intValue: Int?
    var stringValue: String
    
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
    init?(stringValue: String) { self.stringValue = stringValue }
    
    static func makeKey(name: String) -> GenericCodingKeys {
        return GenericCodingKeys(stringValue: name)!
    }
}

//MARK: Decoding container

private struct Unboxable<T>: Swift.Decodable {
    
    let item: ItemResult<T>
    
    init(from decoder: Decoder) throws {
        let unboxing = decoder.userInfo[CodingUserInfoKey(rawValue: "fieldUnboxer")!] as! (() -> FieldMapping)
        let creator = decoder.userInfo[CodingUserInfoKey(rawValue: "creator")!] as! ((UnboxedFields) -> T)
        
        do {
            let fields = try Unboxable.unboxableFields(fromDecoder: decoder, withUnboxing: unboxing)
            item = .success(creator(fields))
        } catch {
            item = .error(error as! DecodingError)
        }
    }
    
    static func unboxableFields(fromDecoder decoder: Decoder, withUnboxing unboxing: (() -> FieldMapping)) throws -> UnboxedFields {
        
        func getValue<T>(fromDictionary dict: [String:T?], forLocale locale: Locale?) -> T? {
            if let locale = locale {
                for testKey in [locale.favouredLocale.rawValue, locale.fallbackLocale.rawValue] {
                    if let value = dict[testKey] {
                        return value
                    }
                }
                
                return nil
                
            } else if let key = dict.keys.first {
                return dict[key]!
            }
            return nil
        }
        
        var unboxedFields: UnboxedFields = [:]
        
        let container = try decoder.container(keyedBy: EntryCodingKeys.self)
        
        let sys = try container.nestedContainer(keyedBy: EntrySysCodingKeys.self, forKey: .sys)
        
        unboxedFields["id"] = try sys.decode(String.self, forKey: .id)
        unboxedFields["version"] = try sys.decode(Int.self, forKey: .version)
        
        let locale = decoder.userInfo[CodingUserInfoKey(rawValue: "locale")!] as? Locale
        let fields = try container.nestedContainer(keyedBy: GenericCodingKeys.self, forKey: .fields)
        let fieldMapping = unboxing()
        let requiredFields = fieldMapping.filter{ $0.value.1 == true }
        let requiredKeys  = Set(requiredFields.keys)
        let fieldsReturned = Set(fields.allKeys.map { $0.stringValue })
        
        guard requiredKeys.isSubset(of: fieldsReturned) else {
            throw DecodingError.missingRequiredFields(Array(requiredKeys.subtracting(fieldsReturned)))
        }
        
        for key in fields.allKeys {
            let field = key.stringValue
            
            if let (type, required) = fieldMapping[field] {
                switch type {
                case .string:
                    let stringDict = try fields.decode(StringDict.self, forKey: key)
                    unboxedFields[field] = getValue(fromDictionary: stringDict, forLocale: locale)
                case .int:
                    let intDict = try fields.decode(IntDict.self, forKey: key)
                    unboxedFields[field] = getValue(fromDictionary: intDict, forLocale : locale)
                case .bool:
                    let boolDict = try fields.decode(BoolDict.self, forKey: key)
                    unboxedFields[field] = getValue(fromDictionary : boolDict, forLocale : locale)
                case .decimal:
                    let doubleDict = try fields.decode(DoubleDict.self, forKey: key)
                    unboxedFields[field] = getValue(fromDictionary: doubleDict, forLocale : locale)
                case .date:
                    let stringDict = try fields.decode(StringDict.self, forKey: key)
                    let dateString = getValue(fromDictionary: stringDict, forLocale : locale)
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = .withFullDate
                    
                    if let ds = dateString {
                        if let date = formatter.date(from: ds) {
                            unboxedFields[field] = date
                        } else {
                            throw DecodingError.fieldFormatError(key.stringValue)
                        }
                    }
                    
                case .oneToOneRef:
                    let oneRefDict = try fields.decode(OneRefDict.self, forKey: key)
                    
                    if let sysDict  = getValue(fromDictionary: oneRefDict, forLocale: locale) {
                        guard let idDict = sysDict["sys"],
                            let id = idDict["id"], let unwrappedId = id,  let type = idDict["linkType"], let unwrappedType = type else {
                                throw DecodingError.typeMismatch(key.stringValue, .oneToOneRef)
                        }
                        
                        unboxedFields[field] = Reference(withId: unwrappedId, type: unwrappedType)
                    }
                    
                case .oneToManyRef:
                    let manyRefDict = try fields.decode(ManyRefDict.self, forKey: key)
                    
                    if let sysDicts = getValue(fromDictionary: manyRefDict, forLocale: locale) {
                        let idDicts = sysDicts.flatMap {  $0["sys"]  }
                        
                        let ids  = idDicts.flatMap { $0["id"]  }.flatMap {$0}
                        let types = idDicts.flatMap { $0["linkType"]}.flatMap{$0}
                        
                        guard ids.count == types.count else { throw DecodingError.typeMismatch(key.stringValue, .oneToManyRef) }
                        
                        let zipped = Array(zip(ids,types))
                        let references = zipped.map { Reference(withId: $0.0, type: $0.1)}
                        unboxedFields[field] = references
                    }
                }
                
                if required && unboxedFields[field] == nil {
                    throw DecodingError.requiredKeyMissing(key.stringValue)
                }
            }
        }
        
        return unboxedFields
    }
}
