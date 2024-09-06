#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef struct {
    uint8_t JmpInstruction[3];
    uint8_t OEM[8]; 
    uint16_t bytes_per_sector;
    uint8_t sectors_per_cluster; 
    uint16_t reserved_sectors_count;
    uint8_t FATs_count; 
    uint16_t root_directory_entry_count; 
    uint16_t total_sectors; 
    uint8_t media_indicator;
    uint16_t sectors_per_FAT_count; 
    uint16_t sectors_per_track_count;
    uint16_t heads_count; 
    uint32_t hidden_sectors_count; 
    uint32_t large_sectors_count;

    uint8_t drive_number; 
    uint8_t flags;
    uint8_t signature;
    uint32_t volume_id ;
    uint8_t volume_label[11];
    uint8_t file_system_type[8];
} __attribute__((packed)) BootSector;

typedef struct {
    uint8_t filename[11];
    uint8_t attribute;
    uint8_t reserved;
    uint8_t creation_time_msec;
    uint16_t creation_time;
    uint16_t creation_date;
    uint16_t last_accessed_date;
    uint16_t first_cluster_number_high;             // always 0 for FAT-12 and FAT-16
    uint16_t last_modification_time;
    uint16_t last_modification_date;
    uint16_t first_cluster_number_low;
    uint32_t file_size;
} __attribute__((packed)) DirectoryEntry;


BootSector g_BootSector;
uint8_t *g_FAT = NULL;
DirectoryEntry *g_RootDirectoryEntries = NULL;
uint16_t g_DataBaseLBA;

bool readBootSector(FILE *disk){
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

bool readSector(FILE *disk, uint16_t lba, uint16_t sector_count, void* buffer){
    bool ok = true;
    ok = ok && (fseek(disk, lba * g_BootSector.bytes_per_sector, SEEK_SET) == 0);
    ok = ok && (fread(buffer, g_BootSector.bytes_per_sector, sector_count, disk) == sector_count);
    return ok;
}

bool readFAT(FILE *disk){
    g_FAT = (uint8_t *)malloc(g_BootSector.sectors_per_FAT_count * g_BootSector.bytes_per_sector);
    return readSector(disk, g_BootSector.reserved_sectors_count, g_BootSector.sectors_per_FAT_count, g_FAT); // Because in FAT-12: Reserve sector -> FAT -> Root directory -> Data
}

bool loadRootDirectoryEntries(FILE *disk){
    uint16_t sector_count = (g_BootSector.root_directory_entry_count + 15) / 16; // There should be 16 entries in a sector by plus 15 we can ceil the number
    uint16_t lba = g_BootSector.reserved_sectors_count + g_BootSector.FATs_count * g_BootSector.sectors_per_FAT_count;
    g_DataBaseLBA = lba + sector_count;
    g_RootDirectoryEntries = (DirectoryEntry *)malloc(sector_count * 512);
    return readSector(disk, lba, sector_count, g_RootDirectoryEntries);
}

DirectoryEntry *getEntryFromFilename(const char* filename){
    for (uint16_t i = 0; i < g_BootSector.root_directory_entry_count; ++i){
        if (memcmp(filename, g_RootDirectoryEntries[i].filename, 11) == 0){
            return &g_RootDirectoryEntries[i];
        }
    }
    return NULL;
}

bool readFile(FILE *disk, DirectoryEntry *fileEntry, uint8_t *buffer){
    bool ok = true;
    uint16_t currentCluster = fileEntry->first_cluster_number_low;
    do{
        // Read the current cluster
        uint16_t lba = ((currentCluster - 2) * g_BootSector.sectors_per_cluster) + g_DataBaseLBA;
        ok = ok && readSector(disk, lba, g_BootSector.sectors_per_cluster, buffer);
        buffer = buffer + g_BootSector.sectors_per_cluster * g_BootSector.bytes_per_sector;

        // Calculate the next cluster
        uint16_t fatIndex = currentCluster * 3 / 2;
        if (currentCluster & 1){
            currentCluster = (*(uint16_t *)(g_FAT + fatIndex)) >> 4;
        }
        else{
            currentCluster = (*(uint16_t *)(g_FAT + fatIndex)) & 0xFFF;
        }
    } while(ok && currentCluster < 0xFF8);
    return ok;
}

int main(int argc, char* argv[]){
    if (argc != 3){
        printf("%s <disk image> <file name>", argv[0]);
        return -1;
    }
    // Read the disk image
    FILE *disk = fopen(argv[1], "rb");
    if(!disk){
        fprintf(stderr, "Disk image %s not exist\n", argv[1]);
        return -1;
    }

    // Map the first sector of image which is the boot sector
    if(!readBootSector(disk)){
        fprintf(stderr, "Cannot read disk image %s \n", argv[1]);
        fclose(disk);
        return -2;
    }
    printf("Reading %s Disk whose File System is %s\n", g_BootSector.volume_label, g_BootSector.file_system_type);

    if(!readFAT(disk)){
        fprintf(stderr, "Cannot read FAT sectors\n");
        fclose(disk);
        free(g_FAT);
        return -3;
    }

    if(!loadRootDirectoryEntries(disk)){
        fprintf(stderr, "Cannot load root directory entries\n");
        fclose(disk);
        free(g_FAT);
        free(g_RootDirectoryEntries);
        return -4;
    }

    DirectoryEntry *myFileEntry = getEntryFromFilename(argv[2]);
    if(myFileEntry == NULL){
        fprintf(stderr, "Cannot get file entry of filename %s\n", argv[2]);
        fclose(disk);
        free(g_FAT);
        free(g_RootDirectoryEntries);
        return -5;
    }

    uint8_t *fileBuffer = (uint8_t *)malloc(myFileEntry->file_size + g_BootSector.bytes_per_sector); // add 512 bytes to make sure that the whole last sector could be load otherwise it would written over g_RootDirectoryEntries
    if(!readFile(disk, myFileEntry, fileBuffer)){
        fprintf(stderr, "Cannot read file of filename %s\n", argv[2]);
        fclose(disk);
        free(g_FAT);
        free(g_RootDirectoryEntries);
        free(fileBuffer);
        return -5;
    }

    for(size_t i = 0; i < myFileEntry->file_size; ++i){
        if(isprint(fileBuffer[i])) fputc(fileBuffer[i], stdout);
        else fprintf(stdout, "\\x%02x", fileBuffer[i]);
    }
    fputc('\n', stdout);
    free(fileBuffer);
    free(g_FAT);
    free(g_RootDirectoryEntries);
    fclose(disk);
    return 0;
}