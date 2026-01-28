// Generated using the ObjectBox Swift Generator — https://objectbox.io
// DO NOT EDIT

// swiftlint:disable all
import ObjectBox
import Foundation

// MARK: - Entity metadata


extension ServiceFileEntry: ObjectBox.__EntityRelatable {
    internal typealias EntityType = ServiceFileEntry

    internal var _id: EntityId<ServiceFileEntry> {
        return EntityId<ServiceFileEntry>(self.id.value)
    }
}

extension ServiceFileEntry: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = ServiceFileEntryBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "ServiceFileEntry", id: 1)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: ServiceFileEntry.self, id: 1, uid: 6523160760332935424)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 2253414601196038144)
        try entityBuilder.addProperty(name: "virtualPath", type: PropertyType.string, flags: [.indexHash, .indexed], id: 2, uid: 3739739575401150208, indexId: 1, indexUid: 1914263140449825280)
        try entityBuilder.addProperty(name: "localPath", type: PropertyType.string, id: 3, uid: 4883201504717826048)
        try entityBuilder.addProperty(name: "externalPath", type: PropertyType.string, id: 4, uid: 2338943473623005440)
        try entityBuilder.addProperty(name: "location", type: PropertyType.long, id: 5, uid: 6556215519676730624)
        try entityBuilder.addProperty(name: "size", type: PropertyType.long, id: 6, uid: 2839541951513324800)
        try entityBuilder.addProperty(name: "createdAt", type: PropertyType.date, id: 7, uid: 6740839692599499008)
        try entityBuilder.addProperty(name: "modifiedAt", type: PropertyType.date, id: 8, uid: 4167846886768930816)
        try entityBuilder.addProperty(name: "accessedAt", type: PropertyType.date, id: 9, uid: 1554881577085474048)
        try entityBuilder.addProperty(name: "checksum", type: PropertyType.string, id: 10, uid: 7473478053128636416)
        try entityBuilder.addProperty(name: "isDirty", type: PropertyType.bool, id: 11, uid: 426354863782007040)
        try entityBuilder.addProperty(name: "isDirectory", type: PropertyType.bool, id: 12, uid: 2216813390412348672)
        try entityBuilder.addProperty(name: "syncPairId", type: PropertyType.string, flags: [.indexHash, .indexed], id: 13, uid: 5719259272208382720, indexId: 2, indexUid: 1013210664427496960)
        try entityBuilder.addProperty(name: "lockState", type: PropertyType.long, id: 14, uid: 1883274516743287040)
        try entityBuilder.addProperty(name: "lockTime", type: PropertyType.date, id: 15, uid: 4658160339947214080)
        try entityBuilder.addProperty(name: "lockDirection", type: PropertyType.long, id: 16, uid: 7632578806194930432)

        try entityBuilder.lastProperty(id: 16, uid: 7632578806194930432)
    }
}

extension ServiceFileEntry {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.id == myId }
    internal static var id: Property<ServiceFileEntry, Id, Id> { return Property<ServiceFileEntry, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.virtualPath.startsWith("X") }
    internal static var virtualPath: Property<ServiceFileEntry, String, Void> { return Property<ServiceFileEntry, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.localPath.startsWith("X") }
    internal static var localPath: Property<ServiceFileEntry, String?, Void> { return Property<ServiceFileEntry, String?, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.externalPath.startsWith("X") }
    internal static var externalPath: Property<ServiceFileEntry, String?, Void> { return Property<ServiceFileEntry, String?, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.location > 1234 }
    internal static var location: Property<ServiceFileEntry, Int, Void> { return Property<ServiceFileEntry, Int, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.size > 1234 }
    internal static var size: Property<ServiceFileEntry, Int64, Void> { return Property<ServiceFileEntry, Int64, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.createdAt > 1234 }
    internal static var createdAt: Property<ServiceFileEntry, Date, Void> { return Property<ServiceFileEntry, Date, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.modifiedAt > 1234 }
    internal static var modifiedAt: Property<ServiceFileEntry, Date, Void> { return Property<ServiceFileEntry, Date, Void>(propertyId: 8, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.accessedAt > 1234 }
    internal static var accessedAt: Property<ServiceFileEntry, Date, Void> { return Property<ServiceFileEntry, Date, Void>(propertyId: 9, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.checksum.startsWith("X") }
    internal static var checksum: Property<ServiceFileEntry, String?, Void> { return Property<ServiceFileEntry, String?, Void>(propertyId: 10, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.isDirty == true }
    internal static var isDirty: Property<ServiceFileEntry, Bool, Void> { return Property<ServiceFileEntry, Bool, Void>(propertyId: 11, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.isDirectory == true }
    internal static var isDirectory: Property<ServiceFileEntry, Bool, Void> { return Property<ServiceFileEntry, Bool, Void>(propertyId: 12, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.syncPairId.startsWith("X") }
    internal static var syncPairId: Property<ServiceFileEntry, String, Void> { return Property<ServiceFileEntry, String, Void>(propertyId: 13, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.lockState > 1234 }
    internal static var lockState: Property<ServiceFileEntry, Int, Void> { return Property<ServiceFileEntry, Int, Void>(propertyId: 14, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.lockTime > 1234 }
    internal static var lockTime: Property<ServiceFileEntry, Date?, Void> { return Property<ServiceFileEntry, Date?, Void>(propertyId: 15, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceFileEntry.lockDirection > 1234 }
    internal static var lockDirection: Property<ServiceFileEntry, Int?, Void> { return Property<ServiceFileEntry, Int?, Void>(propertyId: 16, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == ServiceFileEntry {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<ServiceFileEntry, Id, Id> { return Property<ServiceFileEntry, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .virtualPath.startsWith("X") }

    internal static var virtualPath: Property<ServiceFileEntry, String, Void> { return Property<ServiceFileEntry, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .localPath.startsWith("X") }

    internal static var localPath: Property<ServiceFileEntry, String?, Void> { return Property<ServiceFileEntry, String?, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .externalPath.startsWith("X") }

    internal static var externalPath: Property<ServiceFileEntry, String?, Void> { return Property<ServiceFileEntry, String?, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .location > 1234 }

    internal static var location: Property<ServiceFileEntry, Int, Void> { return Property<ServiceFileEntry, Int, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .size > 1234 }

    internal static var size: Property<ServiceFileEntry, Int64, Void> { return Property<ServiceFileEntry, Int64, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .createdAt > 1234 }

    internal static var createdAt: Property<ServiceFileEntry, Date, Void> { return Property<ServiceFileEntry, Date, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .modifiedAt > 1234 }

    internal static var modifiedAt: Property<ServiceFileEntry, Date, Void> { return Property<ServiceFileEntry, Date, Void>(propertyId: 8, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .accessedAt > 1234 }

    internal static var accessedAt: Property<ServiceFileEntry, Date, Void> { return Property<ServiceFileEntry, Date, Void>(propertyId: 9, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .checksum.startsWith("X") }

    internal static var checksum: Property<ServiceFileEntry, String?, Void> { return Property<ServiceFileEntry, String?, Void>(propertyId: 10, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .isDirty == true }

    internal static var isDirty: Property<ServiceFileEntry, Bool, Void> { return Property<ServiceFileEntry, Bool, Void>(propertyId: 11, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .isDirectory == true }

    internal static var isDirectory: Property<ServiceFileEntry, Bool, Void> { return Property<ServiceFileEntry, Bool, Void>(propertyId: 12, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .syncPairId.startsWith("X") }

    internal static var syncPairId: Property<ServiceFileEntry, String, Void> { return Property<ServiceFileEntry, String, Void>(propertyId: 13, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .lockState > 1234 }

    internal static var lockState: Property<ServiceFileEntry, Int, Void> { return Property<ServiceFileEntry, Int, Void>(propertyId: 14, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .lockTime > 1234 }

    internal static var lockTime: Property<ServiceFileEntry, Date?, Void> { return Property<ServiceFileEntry, Date?, Void>(propertyId: 15, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .lockDirection > 1234 }

    internal static var lockDirection: Property<ServiceFileEntry, Int?, Void> { return Property<ServiceFileEntry, Int?, Void>(propertyId: 16, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `ServiceFileEntry.EntityBindingType`.
internal final class ServiceFileEntryBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = ServiceFileEntry
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_virtualPath = propertyCollector.prepare(string: entity.virtualPath)
        let propertyOffset_localPath = propertyCollector.prepare(string: entity.localPath)
        let propertyOffset_externalPath = propertyCollector.prepare(string: entity.externalPath)
        let propertyOffset_checksum = propertyCollector.prepare(string: entity.checksum)
        let propertyOffset_syncPairId = propertyCollector.prepare(string: entity.syncPairId)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.location, at: 2 + 2 * 5)
        propertyCollector.collect(entity.size, at: 2 + 2 * 6)
        propertyCollector.collect(entity.createdAt, at: 2 + 2 * 7)
        propertyCollector.collect(entity.modifiedAt, at: 2 + 2 * 8)
        propertyCollector.collect(entity.accessedAt, at: 2 + 2 * 9)
        propertyCollector.collect(entity.isDirty, at: 2 + 2 * 11)
        propertyCollector.collect(entity.isDirectory, at: 2 + 2 * 12)
        propertyCollector.collect(entity.lockState, at: 2 + 2 * 14)
        propertyCollector.collect(entity.lockTime, at: 2 + 2 * 15)
        propertyCollector.collect(entity.lockDirection, at: 2 + 2 * 16)
        propertyCollector.collect(dataOffset: propertyOffset_virtualPath, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_localPath, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_externalPath, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_checksum, at: 2 + 2 * 10)
        propertyCollector.collect(dataOffset: propertyOffset_syncPairId, at: 2 + 2 * 13)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = ServiceFileEntry()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.virtualPath = entityReader.read(at: 2 + 2 * 2)
        entity.localPath = entityReader.read(at: 2 + 2 * 3)
        entity.externalPath = entityReader.read(at: 2 + 2 * 4)
        entity.location = entityReader.read(at: 2 + 2 * 5)
        entity.size = entityReader.read(at: 2 + 2 * 6)
        entity.createdAt = entityReader.read(at: 2 + 2 * 7)
        entity.modifiedAt = entityReader.read(at: 2 + 2 * 8)
        entity.accessedAt = entityReader.read(at: 2 + 2 * 9)
        entity.checksum = entityReader.read(at: 2 + 2 * 10)
        entity.isDirty = entityReader.read(at: 2 + 2 * 11)
        entity.isDirectory = entityReader.read(at: 2 + 2 * 12)
        entity.syncPairId = entityReader.read(at: 2 + 2 * 13)
        entity.lockState = entityReader.read(at: 2 + 2 * 14)
        entity.lockTime = entityReader.read(at: 2 + 2 * 15)
        entity.lockDirection = entityReader.read(at: 2 + 2 * 16)

        return entity
    }
}



extension ServiceSyncHistory: ObjectBox.__EntityRelatable {
    internal typealias EntityType = ServiceSyncHistory

    internal var _id: EntityId<ServiceSyncHistory> {
        return EntityId<ServiceSyncHistory>(self.id.value)
    }
}

extension ServiceSyncHistory: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = ServiceSyncHistoryBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "ServiceSyncHistory", id: 2)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: ServiceSyncHistory.self, id: 2, uid: 5546110147861545216)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 9048534855598341632)
        try entityBuilder.addProperty(name: "syncPairId", type: PropertyType.string, flags: [.indexHash, .indexed], id: 2, uid: 7902501728545585920, indexId: 3, indexUid: 1611844169087301376)
        try entityBuilder.addProperty(name: "diskId", type: PropertyType.string, id: 3, uid: 8704595903928023552)
        try entityBuilder.addProperty(name: "startTime", type: PropertyType.date, flags: [.indexed], id: 4, uid: 9209406812942102784, indexId: 4, indexUid: 2062295401991771136)
        try entityBuilder.addProperty(name: "endTime", type: PropertyType.date, id: 5, uid: 4728022604082098688)
        try entityBuilder.addProperty(name: "status", type: PropertyType.long, id: 6, uid: 7443159110585213696)
        try entityBuilder.addProperty(name: "direction", type: PropertyType.long, id: 7, uid: 9001854343434633984)
        try entityBuilder.addProperty(name: "totalFiles", type: PropertyType.long, id: 8, uid: 5524101397852849152)
        try entityBuilder.addProperty(name: "filesUpdated", type: PropertyType.long, id: 9, uid: 4951718239270053632)
        try entityBuilder.addProperty(name: "filesDeleted", type: PropertyType.long, id: 10, uid: 7627945492807191808)
        try entityBuilder.addProperty(name: "filesSkipped", type: PropertyType.long, id: 11, uid: 4248757896395226880)
        try entityBuilder.addProperty(name: "bytesTransferred", type: PropertyType.long, id: 12, uid: 2285316207016390912)
        try entityBuilder.addProperty(name: "errorMessage", type: PropertyType.string, id: 13, uid: 5835790924020346624)

        try entityBuilder.lastProperty(id: 13, uid: 5835790924020346624)
    }
}

extension ServiceSyncHistory {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.id == myId }
    internal static var id: Property<ServiceSyncHistory, Id, Id> { return Property<ServiceSyncHistory, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.syncPairId.startsWith("X") }
    internal static var syncPairId: Property<ServiceSyncHistory, String, Void> { return Property<ServiceSyncHistory, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.diskId.startsWith("X") }
    internal static var diskId: Property<ServiceSyncHistory, String, Void> { return Property<ServiceSyncHistory, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.startTime > 1234 }
    internal static var startTime: Property<ServiceSyncHistory, Date, Void> { return Property<ServiceSyncHistory, Date, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.endTime > 1234 }
    internal static var endTime: Property<ServiceSyncHistory, Date?, Void> { return Property<ServiceSyncHistory, Date?, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.status > 1234 }
    internal static var status: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.direction > 1234 }
    internal static var direction: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.totalFiles > 1234 }
    internal static var totalFiles: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 8, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.filesUpdated > 1234 }
    internal static var filesUpdated: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 9, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.filesDeleted > 1234 }
    internal static var filesDeleted: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 10, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.filesSkipped > 1234 }
    internal static var filesSkipped: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 11, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.bytesTransferred > 1234 }
    internal static var bytesTransferred: Property<ServiceSyncHistory, Int64, Void> { return Property<ServiceSyncHistory, Int64, Void>(propertyId: 12, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncHistory.errorMessage.startsWith("X") }
    internal static var errorMessage: Property<ServiceSyncHistory, String?, Void> { return Property<ServiceSyncHistory, String?, Void>(propertyId: 13, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == ServiceSyncHistory {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<ServiceSyncHistory, Id, Id> { return Property<ServiceSyncHistory, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .syncPairId.startsWith("X") }

    internal static var syncPairId: Property<ServiceSyncHistory, String, Void> { return Property<ServiceSyncHistory, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .diskId.startsWith("X") }

    internal static var diskId: Property<ServiceSyncHistory, String, Void> { return Property<ServiceSyncHistory, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .startTime > 1234 }

    internal static var startTime: Property<ServiceSyncHistory, Date, Void> { return Property<ServiceSyncHistory, Date, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .endTime > 1234 }

    internal static var endTime: Property<ServiceSyncHistory, Date?, Void> { return Property<ServiceSyncHistory, Date?, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .status > 1234 }

    internal static var status: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .direction > 1234 }

    internal static var direction: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .totalFiles > 1234 }

    internal static var totalFiles: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 8, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .filesUpdated > 1234 }

    internal static var filesUpdated: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 9, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .filesDeleted > 1234 }

    internal static var filesDeleted: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 10, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .filesSkipped > 1234 }

    internal static var filesSkipped: Property<ServiceSyncHistory, Int, Void> { return Property<ServiceSyncHistory, Int, Void>(propertyId: 11, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .bytesTransferred > 1234 }

    internal static var bytesTransferred: Property<ServiceSyncHistory, Int64, Void> { return Property<ServiceSyncHistory, Int64, Void>(propertyId: 12, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .errorMessage.startsWith("X") }

    internal static var errorMessage: Property<ServiceSyncHistory, String?, Void> { return Property<ServiceSyncHistory, String?, Void>(propertyId: 13, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `ServiceSyncHistory.EntityBindingType`.
internal final class ServiceSyncHistoryBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = ServiceSyncHistory
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_syncPairId = propertyCollector.prepare(string: entity.syncPairId)
        let propertyOffset_diskId = propertyCollector.prepare(string: entity.diskId)
        let propertyOffset_errorMessage = propertyCollector.prepare(string: entity.errorMessage)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.startTime, at: 2 + 2 * 4)
        propertyCollector.collect(entity.endTime, at: 2 + 2 * 5)
        propertyCollector.collect(entity.status, at: 2 + 2 * 6)
        propertyCollector.collect(entity.direction, at: 2 + 2 * 7)
        propertyCollector.collect(entity.totalFiles, at: 2 + 2 * 8)
        propertyCollector.collect(entity.filesUpdated, at: 2 + 2 * 9)
        propertyCollector.collect(entity.filesDeleted, at: 2 + 2 * 10)
        propertyCollector.collect(entity.filesSkipped, at: 2 + 2 * 11)
        propertyCollector.collect(entity.bytesTransferred, at: 2 + 2 * 12)
        propertyCollector.collect(dataOffset: propertyOffset_syncPairId, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_diskId, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_errorMessage, at: 2 + 2 * 13)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = ServiceSyncHistory()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.syncPairId = entityReader.read(at: 2 + 2 * 2)
        entity.diskId = entityReader.read(at: 2 + 2 * 3)
        entity.startTime = entityReader.read(at: 2 + 2 * 4)
        entity.endTime = entityReader.read(at: 2 + 2 * 5)
        entity.status = entityReader.read(at: 2 + 2 * 6)
        entity.direction = entityReader.read(at: 2 + 2 * 7)
        entity.totalFiles = entityReader.read(at: 2 + 2 * 8)
        entity.filesUpdated = entityReader.read(at: 2 + 2 * 9)
        entity.filesDeleted = entityReader.read(at: 2 + 2 * 10)
        entity.filesSkipped = entityReader.read(at: 2 + 2 * 11)
        entity.bytesTransferred = entityReader.read(at: 2 + 2 * 12)
        entity.errorMessage = entityReader.read(at: 2 + 2 * 13)

        return entity
    }
}



extension ServiceSyncStatistics: ObjectBox.__EntityRelatable {
    internal typealias EntityType = ServiceSyncStatistics

    internal var _id: EntityId<ServiceSyncStatistics> {
        return EntityId<ServiceSyncStatistics>(self.id.value)
    }
}

extension ServiceSyncStatistics: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = ServiceSyncStatisticsBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "ServiceSyncStatistics", id: 3)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: ServiceSyncStatistics.self, id: 3, uid: 6794996534435832064)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 3564937623048296448)
        try entityBuilder.addProperty(name: "date", type: PropertyType.date, flags: [.indexed], id: 2, uid: 8035417422069545728, indexId: 5, indexUid: 6548826889766988544)
        try entityBuilder.addProperty(name: "syncPairId", type: PropertyType.string, flags: [.indexHash, .indexed], id: 3, uid: 129209526642612736, indexId: 6, indexUid: 2853245467694275072)
        try entityBuilder.addProperty(name: "diskId", type: PropertyType.string, id: 4, uid: 8898091481406911232)
        try entityBuilder.addProperty(name: "totalSyncs", type: PropertyType.long, id: 5, uid: 7093678854383734016)
        try entityBuilder.addProperty(name: "successfulSyncs", type: PropertyType.long, id: 6, uid: 9165783164445434112)
        try entityBuilder.addProperty(name: "failedSyncs", type: PropertyType.long, id: 7, uid: 6793078338254398464)
        try entityBuilder.addProperty(name: "totalFilesProcessed", type: PropertyType.long, id: 8, uid: 922367386519213824)
        try entityBuilder.addProperty(name: "totalBytesTransferred", type: PropertyType.long, id: 9, uid: 2768892825480184320)
        try entityBuilder.addProperty(name: "averageDuration", type: PropertyType.double, id: 10, uid: 7617871385796899328)

        try entityBuilder.lastProperty(id: 10, uid: 7617871385796899328)
    }
}

extension ServiceSyncStatistics {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.id == myId }
    internal static var id: Property<ServiceSyncStatistics, Id, Id> { return Property<ServiceSyncStatistics, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.date > 1234 }
    internal static var date: Property<ServiceSyncStatistics, Date, Void> { return Property<ServiceSyncStatistics, Date, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.syncPairId.startsWith("X") }
    internal static var syncPairId: Property<ServiceSyncStatistics, String, Void> { return Property<ServiceSyncStatistics, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.diskId.startsWith("X") }
    internal static var diskId: Property<ServiceSyncStatistics, String, Void> { return Property<ServiceSyncStatistics, String, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.totalSyncs > 1234 }
    internal static var totalSyncs: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.successfulSyncs > 1234 }
    internal static var successfulSyncs: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.failedSyncs > 1234 }
    internal static var failedSyncs: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.totalFilesProcessed > 1234 }
    internal static var totalFilesProcessed: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 8, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.totalBytesTransferred > 1234 }
    internal static var totalBytesTransferred: Property<ServiceSyncStatistics, Int64, Void> { return Property<ServiceSyncStatistics, Int64, Void>(propertyId: 9, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { ServiceSyncStatistics.averageDuration > 1234 }
    internal static var averageDuration: Property<ServiceSyncStatistics, Double, Void> { return Property<ServiceSyncStatistics, Double, Void>(propertyId: 10, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == ServiceSyncStatistics {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<ServiceSyncStatistics, Id, Id> { return Property<ServiceSyncStatistics, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .date > 1234 }

    internal static var date: Property<ServiceSyncStatistics, Date, Void> { return Property<ServiceSyncStatistics, Date, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .syncPairId.startsWith("X") }

    internal static var syncPairId: Property<ServiceSyncStatistics, String, Void> { return Property<ServiceSyncStatistics, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .diskId.startsWith("X") }

    internal static var diskId: Property<ServiceSyncStatistics, String, Void> { return Property<ServiceSyncStatistics, String, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .totalSyncs > 1234 }

    internal static var totalSyncs: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .successfulSyncs > 1234 }

    internal static var successfulSyncs: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .failedSyncs > 1234 }

    internal static var failedSyncs: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .totalFilesProcessed > 1234 }

    internal static var totalFilesProcessed: Property<ServiceSyncStatistics, Int, Void> { return Property<ServiceSyncStatistics, Int, Void>(propertyId: 8, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .totalBytesTransferred > 1234 }

    internal static var totalBytesTransferred: Property<ServiceSyncStatistics, Int64, Void> { return Property<ServiceSyncStatistics, Int64, Void>(propertyId: 9, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .averageDuration > 1234 }

    internal static var averageDuration: Property<ServiceSyncStatistics, Double, Void> { return Property<ServiceSyncStatistics, Double, Void>(propertyId: 10, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `ServiceSyncStatistics.EntityBindingType`.
internal final class ServiceSyncStatisticsBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = ServiceSyncStatistics
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_syncPairId = propertyCollector.prepare(string: entity.syncPairId)
        let propertyOffset_diskId = propertyCollector.prepare(string: entity.diskId)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.date, at: 2 + 2 * 2)
        propertyCollector.collect(entity.totalSyncs, at: 2 + 2 * 5)
        propertyCollector.collect(entity.successfulSyncs, at: 2 + 2 * 6)
        propertyCollector.collect(entity.failedSyncs, at: 2 + 2 * 7)
        propertyCollector.collect(entity.totalFilesProcessed, at: 2 + 2 * 8)
        propertyCollector.collect(entity.totalBytesTransferred, at: 2 + 2 * 9)
        propertyCollector.collect(entity.averageDuration, at: 2 + 2 * 10)
        propertyCollector.collect(dataOffset: propertyOffset_syncPairId, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_diskId, at: 2 + 2 * 4)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = ServiceSyncStatistics()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.date = entityReader.read(at: 2 + 2 * 2)
        entity.syncPairId = entityReader.read(at: 2 + 2 * 3)
        entity.diskId = entityReader.read(at: 2 + 2 * 4)
        entity.totalSyncs = entityReader.read(at: 2 + 2 * 5)
        entity.successfulSyncs = entityReader.read(at: 2 + 2 * 6)
        entity.failedSyncs = entityReader.read(at: 2 + 2 * 7)
        entity.totalFilesProcessed = entityReader.read(at: 2 + 2 * 8)
        entity.totalBytesTransferred = entityReader.read(at: 2 + 2 * 9)
        entity.averageDuration = entityReader.read(at: 2 + 2 * 10)

        return entity
    }
}


extension ServiceSyncFileRecord: ObjectBox.__EntityRelatable {
    internal typealias EntityType = ServiceSyncFileRecord

    internal var _id: EntityId<ServiceSyncFileRecord> {
        return EntityId<ServiceSyncFileRecord>(self.id.value)
    }
}

extension ServiceSyncFileRecord: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = ServiceSyncFileRecordBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "ServiceSyncFileRecord", id: 4)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: ServiceSyncFileRecord.self, id: 4, uid: 3847291056482719744)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 5182736401928345600)
        try entityBuilder.addProperty(name: "syncPairId", type: PropertyType.string, flags: [.indexHash, .indexed], id: 2, uid: 7293841502637184000, indexId: 7, indexUid: 4519283746102938624)
        try entityBuilder.addProperty(name: "diskId", type: PropertyType.string, flags: [.indexHash, .indexed], id: 3, uid: 8401927365482918912, indexId: 8, indexUid: 6738291045827364864)
        try entityBuilder.addProperty(name: "virtualPath", type: PropertyType.string, flags: [.indexHash, .indexed], id: 4, uid: 1928374650192837632, indexId: 9, indexUid: 8192736450182736384)
        try entityBuilder.addProperty(name: "fileSize", type: PropertyType.long, id: 5, uid: 3019284756019283456)
        try entityBuilder.addProperty(name: "syncedAt", type: PropertyType.date, flags: [.indexed], id: 6, uid: 4102938475601928192, indexId: 10, indexUid: 9283746501928374272)
        try entityBuilder.addProperty(name: "status", type: PropertyType.long, id: 7, uid: 5201938475610293760)
        try entityBuilder.addProperty(name: "errorMessage", type: PropertyType.string, id: 8, uid: 6302948576710394368)
        try entityBuilder.addProperty(name: "syncTaskId", type: PropertyType.long, id: 9, uid: 7403958677810495488)

        try entityBuilder.lastProperty(id: 9, uid: 7403958677810495488)
    }
}

extension ServiceSyncFileRecord {
    internal static var id: Property<ServiceSyncFileRecord, Id, Id> { return Property<ServiceSyncFileRecord, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    internal static var syncPairId: Property<ServiceSyncFileRecord, String, Void> { return Property<ServiceSyncFileRecord, String, Void>(propertyId: 2, isPrimaryKey: false) }
    internal static var diskId: Property<ServiceSyncFileRecord, String, Void> { return Property<ServiceSyncFileRecord, String, Void>(propertyId: 3, isPrimaryKey: false) }
    internal static var virtualPath: Property<ServiceSyncFileRecord, String, Void> { return Property<ServiceSyncFileRecord, String, Void>(propertyId: 4, isPrimaryKey: false) }
    internal static var fileSize: Property<ServiceSyncFileRecord, Int64, Void> { return Property<ServiceSyncFileRecord, Int64, Void>(propertyId: 5, isPrimaryKey: false) }
    internal static var syncedAt: Property<ServiceSyncFileRecord, Date, Void> { return Property<ServiceSyncFileRecord, Date, Void>(propertyId: 6, isPrimaryKey: false) }
    internal static var status: Property<ServiceSyncFileRecord, Int, Void> { return Property<ServiceSyncFileRecord, Int, Void>(propertyId: 7, isPrimaryKey: false) }
    internal static var errorMessage: Property<ServiceSyncFileRecord, String?, Void> { return Property<ServiceSyncFileRecord, String?, Void>(propertyId: 8, isPrimaryKey: false) }
    internal static var syncTaskId: Property<ServiceSyncFileRecord, UInt64, Void> { return Property<ServiceSyncFileRecord, UInt64, Void>(propertyId: 9, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == ServiceSyncFileRecord {
    internal static var id: Property<ServiceSyncFileRecord, Id, Id> { return Property<ServiceSyncFileRecord, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    internal static var syncPairId: Property<ServiceSyncFileRecord, String, Void> { return Property<ServiceSyncFileRecord, String, Void>(propertyId: 2, isPrimaryKey: false) }
    internal static var diskId: Property<ServiceSyncFileRecord, String, Void> { return Property<ServiceSyncFileRecord, String, Void>(propertyId: 3, isPrimaryKey: false) }
    internal static var virtualPath: Property<ServiceSyncFileRecord, String, Void> { return Property<ServiceSyncFileRecord, String, Void>(propertyId: 4, isPrimaryKey: false) }
    internal static var fileSize: Property<ServiceSyncFileRecord, Int64, Void> { return Property<ServiceSyncFileRecord, Int64, Void>(propertyId: 5, isPrimaryKey: false) }
    internal static var syncedAt: Property<ServiceSyncFileRecord, Date, Void> { return Property<ServiceSyncFileRecord, Date, Void>(propertyId: 6, isPrimaryKey: false) }
    internal static var status: Property<ServiceSyncFileRecord, Int, Void> { return Property<ServiceSyncFileRecord, Int, Void>(propertyId: 7, isPrimaryKey: false) }
    internal static var errorMessage: Property<ServiceSyncFileRecord, String?, Void> { return Property<ServiceSyncFileRecord, String?, Void>(propertyId: 8, isPrimaryKey: false) }
    internal static var syncTaskId: Property<ServiceSyncFileRecord, UInt64, Void> { return Property<ServiceSyncFileRecord, UInt64, Void>(propertyId: 9, isPrimaryKey: false) }
}


/// Generated service type to handle persisting and reading entity data. Exposed through `ServiceSyncFileRecord.EntityBindingType`.
internal final class ServiceSyncFileRecordBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = ServiceSyncFileRecord
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_syncPairId = propertyCollector.prepare(string: entity.syncPairId)
        let propertyOffset_diskId = propertyCollector.prepare(string: entity.diskId)
        let propertyOffset_virtualPath = propertyCollector.prepare(string: entity.virtualPath)
        let propertyOffset_errorMessage = propertyCollector.prepare(string: entity.errorMessage)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.fileSize, at: 2 + 2 * 5)
        propertyCollector.collect(entity.syncedAt, at: 2 + 2 * 6)
        propertyCollector.collect(entity.status, at: 2 + 2 * 7)
        propertyCollector.collect(entity.syncTaskId, at: 2 + 2 * 9)
        propertyCollector.collect(dataOffset: propertyOffset_syncPairId, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_diskId, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_virtualPath, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_errorMessage, at: 2 + 2 * 8)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = ServiceSyncFileRecord()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.syncPairId = entityReader.read(at: 2 + 2 * 2)
        entity.diskId = entityReader.read(at: 2 + 2 * 3)
        entity.virtualPath = entityReader.read(at: 2 + 2 * 4)
        entity.fileSize = entityReader.read(at: 2 + 2 * 5)
        entity.syncedAt = entityReader.read(at: 2 + 2 * 6)
        entity.status = entityReader.read(at: 2 + 2 * 7)
        entity.errorMessage = entityReader.read(at: 2 + 2 * 8)
        entity.syncTaskId = entityReader.read(at: 2 + 2 * 9)

        return entity
    }
}


/// Helper function that allows calling Enum(rawValue: value) with a nil value, which will return nil.
fileprivate func optConstruct<T: RawRepresentable>(_ type: T.Type, rawValue: T.RawValue?) -> T? {
    guard let rawValue = rawValue else { return nil }
    return T(rawValue: rawValue)
}

// MARK: - Store setup

fileprivate func cModel() throws -> OpaquePointer {
    let modelBuilder = try ObjectBox.ModelBuilder()
    try ServiceFileEntry.buildEntity(modelBuilder: modelBuilder)
    try ServiceSyncHistory.buildEntity(modelBuilder: modelBuilder)
    try ServiceSyncStatistics.buildEntity(modelBuilder: modelBuilder)
    try ServiceSyncFileRecord.buildEntity(modelBuilder: modelBuilder)
    modelBuilder.lastEntity(id: 4, uid: 3847291056482719744)
    modelBuilder.lastIndex(id: 10, uid: 9283746501928374272)
    return modelBuilder.finish()
}

extension ObjectBox.Store {
    /// A store with a fully configured model. Created by the code generator with your model's metadata in place.
    ///
    /// # In-memory database
    /// To use a file-less in-memory database, instead of a directory path pass `memory:` 
    /// together with an identifier string:
    /// ```swift
    /// let inMemoryStore = try Store(directoryPath: "memory:test-db")
    /// ```
    ///
    /// - Parameters:
    ///   - directoryPath: The directory path in which ObjectBox places its database files for this store,
    ///     or to use an in-memory database `memory:<identifier>`.
    ///   - maxDbSizeInKByte: Limit of on-disk space for the database files. Default is `1024 * 1024` (1 GiB).
    ///   - fileMode: UNIX-style bit mask used for the database files; default is `0o644`.
    ///     Note: directories become searchable if the "read" or "write" permission is set (e.g. 0640 becomes 0750).
    ///   - maxReaders: The maximum number of readers.
    ///     "Readers" are a finite resource for which we need to define a maximum number upfront.
    ///     The default value is enough for most apps and usually you can ignore it completely.
    ///     However, if you get the maxReadersExceeded error, you should verify your
    ///     threading. For each thread, ObjectBox uses multiple readers. Their number (per thread) depends
    ///     on number of types, relations, and usage patterns. Thus, if you are working with many threads
    ///     (e.g. in a server-like scenario), it can make sense to increase the maximum number of readers.
    ///     Note: The internal default is currently around 120. So when hitting this limit, try values around 200-500.
    ///   - readOnly: Opens the database in read-only mode, i.e. not allowing write transactions.
    ///
    /// - important: This initializer is created by the code generator. If you only see the internal `init(model:...)`
    ///              initializer, trigger code generation by building your project.
    internal convenience init(directoryPath: String, maxDbSizeInKByte: UInt64 = 1024 * 1024,
                            fileMode: UInt32 = 0o644, maxReaders: UInt32 = 0, readOnly: Bool = false) throws {
        try self.init(
            model: try cModel(),
            directory: directoryPath,
            maxDbSizeInKByte: maxDbSizeInKByte,
            fileMode: fileMode,
            maxReaders: maxReaders,
            readOnly: readOnly)
    }
}

// swiftlint:enable all
